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
- PR が存在する場合: タイトル・URL・ブランチ名（headRefName）を記録して Step 1.5 へ進む

---

## Step 1.5: セッション内 git 書き込み操作の一括承認

このコマンドは `/work` を経由しないため、`task.md`/`patch.md` が持つ session-approved の一括承認ゲートを持たない。そのままだと Step 1.6 以降の `git fetch`/`checkout`/`push` が毎回個別に確認プロンプトを要求する。

ユーザーに確認する:
**「PR #<番号> のレビュー対応を進めます。このセッション中の git 書き込み操作（fetch / checkout / add / commit / push）を自動承認にしてよいですか？」**

- OK の場合:
    - 以下の Bash コマンドで session-approved ファイルの正確なパスを解決する（`hooks/lib/session-paths.sh` が `hooks/lib/session-id.sh` の `session_id_resolve` を再利用して1行で絶対パスを返す。共有ファイル経由では取得しない — 複数セッション同時実行時の混線を避けるため。brace expansion や代入への command substitution をコマンド自体に含めないことで worktree 隔離セッションでの harness 拒否を避ける、issue #316）:
        - Claude Code: `bash ~/.claude/hooks/lib/session-paths.sh session-approved`
        - Codex CLI: `bash ~/.codex/hooks/lib/session-paths.sh session-approved`

      出力された1行の絶対パスを以降 `SESSION_APPROVED_FILE` として扱う。コマンドが失敗した場合（hook が未実行でセッション ID が解決できないケース）はスキップして Step 1.6 へ進む。
    - Write ツールで上記パスに session-approved ファイルを作成する。内容: `tool:git_write`
    - 注: `session-approved` はこの Step で 1 度だけ書き込む。実行中にスコープを追加しようとすると hook がブロックする。スコープ変更が必要な場合はこの Step に戻り、ユーザーの許可を得てから再書き込みすること。
    - このゲートは `tool:git_write`（fetch/checkout/add/commit/非force push 等）のみを対象とする。コメント返信（`gh api ... --method POST`）は対象外で、引き続き通常の許可フローに従う — `gh api` の write 操作は allowlist-shape 上の理由から一律 session-approved 対象外としているため（`docs/L0_concept/policy.md`）。
- NG または回答なしの場合:
    - session-approved ファイルは作成せず、各 git 書き込み操作は通常の許可フローに従う

Step 1.6 へ進む。

---

## Step 1.6: PR ブランチの取得・切り替え

```bash
git fetch origin <headRefName>
git checkout <headRefName>
```

- checkout に失敗した場合: 「ブランチ '<headRefName>' への切り替えに失敗しました。リモートに存在するか確認してください」と報告して終了する
- 成功した場合: Step 2 へ進む

---

## Step 2: レビューコメントの取得

以下の 2 種類を取得する。

### (A) インラインコードコメント（diff に紐づくコメント）

```bash
gh api repos/{owner}/{repo}/pulls/<PR番号>/comments \
  --jq '[.[] | {id: .id, path: .path, line: .line, body: .body, user: .user.login, created_at: .created_at}]'
```

### (B) レビュー本体コメント（CHANGES_REQUESTED / COMMENTED / APPROVED 状態のレビュー）

```bash
gh api repos/{owner}/{repo}/pulls/<PR番号>/reviews \
  --jq '[.[] | select(.state == "CHANGES_REQUESTED" or .state == "COMMENTED" or .state == "APPROVED") | select(.body != "") | {id: .id, state: .state, body: .body, user: .user.login, submitted_at: .submitted_at}]'
```

- `{owner}` と `{repo}` は `gh repo view --json owner,name` で取得する

両方が空（インラインコメント・レビュー・承認いずれも存在しない）の場合:
- 「PR #<番号> にレビューコメントはありません（inline comment・review・approval いずれも未提出）」と報告して終了する

コメントが存在する場合: Step 3 へ進む。

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
状態: CHANGES_REQUESTED / COMMENTED / APPROVED  ← レビューコメントの場合のみ

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
- 実装完了後、`/git-commit` を実行する
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
