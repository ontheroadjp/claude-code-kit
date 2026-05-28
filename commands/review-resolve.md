# /review-resolve

指定した PR のレビューコメントを取得し、各コメントに対して Claude の意見を提示したうえでユーザーが対応方針を選択できるコマンドです。実装・コミット・push まで自己完結します（`/work` は呼びません）。

**使用方法:** `/review-resolve 19` または `/review-resolve #19`

---

## Step 0: 引数チェック

`$ARGUMENTS` から PR 番号を取得する。
- `#19` 形式の場合は `#` を除去して `19` として扱う
- PR 番号が指定されていない場合:
  - 「PR 番号を指定してください。例: `/review-resolve 19`」とユーザーに報告して終了する

---

## Step 1: PR の存在確認

```bash
gh pr view <PR番号> --json number,url,title,headRefName
```

- PR が存在しない場合: 「PR #<番号> が見つかりません」と報告して終了する
- PR が存在する場合: タイトル・URL・ブランチ名（headRefName）を記録して Step 2 へ進む

---

## Step 2: レビューコメントの取得

以下の 2 種類を取得する。

### (A) インラインコードコメント（diff に紐づくコメント）

```bash
gh api repos/{owner}/{repo}/pulls/<PR番号>/comments \
  --jq '[.[] | {id: .id, path: .path, line: .line, body: .body, user: .user.login, created_at: .created_at}]'
```

### (B) レビュー本体コメント（CHANGES_REQUESTED / COMMENTED 状態のレビュー）

```bash
gh api repos/{owner}/{repo}/pulls/<PR番号>/reviews \
  --jq '[.[] | select(.state == "CHANGES_REQUESTED" or .state == "COMMENTED") | select(.body != "") | {id: .id, state: .state, body: .body, user: .user.login, submitted_at: .submitted_at}]'
```

- `{owner}` と `{repo}` は `gh repo view --json owner,name` で取得する

両方が空（コメントなし）の場合:
- 「PR #<番号> にレビューコメントはありません」と報告して終了する

コメントが存在する場合: Step 2 完了後に `git checkout <headRefName>` を実行して PR ブランチに移動する。

---

## Step 3: コメントの提示・意見・対応選択

取得したコメントを **1件ずつ** ユーザーに提示する。

### 提示フォーマット

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[コメント N/全件数]
種別: インラインコメント / レビューコメント
投稿者: @<user>
ファイル: <path>:<line>  ← インラインの場合のみ
状態: CHANGES_REQUESTED / COMMENTED  ← レビューコメントの場合のみ

<コメント本文>

── Claude の意見 ──────────────────
<コメント内容と該当コードを読んだ上での意見を記述する>
例: 指摘は妥当です。〇〇の理由で△△すべきです。
例: この指摘には同意しかねます。△△の理由で現状の実装が適切と考えます。
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

どう対応しますか？
  1. 対応する（このブランチ上で実装）
  2. 反対意見を返信する（Claude の意見をベースに理由をコメントへ投稿）
  3. 対応しない（別の理由をコメントに返信）
  4. スキップ（後で判断）
```

### 選択 1: 対応する

- 該当コードを読み、コメント内容に基づいて実装を行う
- スコープが大きすぎると判断した場合:
  - 「このコメントへの対応はスコープが大きいため、`/work` で別途対応してください」と報告する
  - このコメントをスキップして次へ進む
- 実装完了後、`~/.config/claude-code-kit/partials/git-commit.md` を Read し、その手順に従ってコミットする
  - パラメータ: `issue_number=none`, `allowed_types=[fix, refactor, style]`
- `git push` を実行する
- このコメントへ返信する:
  ```bash
  # インラインコメントへの返信
  gh api repos/{owner}/{repo}/pulls/<PR番号>/comments/<comment_id>/replies \
    --method POST \
    -f body="対応しました。"

  # レビュー本体コメントへの返信（issue comment として投稿）
  gh api repos/{owner}/{repo}/issues/<PR番号>/comments \
    --method POST \
    -f body="対応しました。"
  ```
- 次のコメントへ進む

### 選択 2: 反対意見を返信する

- Claude の意見をベースに返信文を作成してユーザーに提示する
- ユーザーが内容を確認・修正したら、コメントに返信する:
  ```bash
  # インラインコメントへの返信
  gh api repos/{owner}/{repo}/pulls/<PR番号>/comments/<comment_id>/replies \
    --method POST \
    -f body="<返信文>"

  # レビュー本体コメントへの返信
  gh api repos/{owner}/{repo}/issues/<PR番号>/comments \
    --method POST \
    -f body="<返信文>"
  ```
- 「返信しました」と報告して次のコメントへ進む

### 選択 3: 対応しない

- 「返信する理由・説明を入力してください:」とユーザーに入力を促す
- 入力された理由をコメントに返信する:
  ```bash
  # インラインコメントへの返信
  gh api repos/{owner}/{repo}/pulls/<PR番号>/comments/<comment_id>/replies \
    --method POST \
    -f body="<ユーザーが入力した理由>"

  # レビュー本体コメントへの返信
  gh api repos/{owner}/{repo}/issues/<PR番号>/comments \
    --method POST \
    -f body="<ユーザーが入力した理由>"
  ```
- 「返信しました」と報告して次のコメントへ進む

### 選択 4: スキップ

- そのコメントには何もせず次のコメントへ進む

---

## Step 4: 完了報告

全コメントの処理が完了したら以下を報告する:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
レビュー対応完了 — PR #<番号>

対応した:        N 件 → 実装・コミット・push 済み
反対意見を返信:  N 件 → 理由をコメントに投稿済み
返信した:        N 件 → 理由をコメントに投稿済み
スキップした:    N 件 → 未対応
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

スキップしたコメントが 1 件以上ある場合:
- 「スキップしたコメントがあります。PR #<番号> を確認してください: <URL>」と追記する
