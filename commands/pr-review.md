# /pr-review

指定した PR を実装元とは別の AI agent でレビューし、妥当な指摘を承認済みスコープ内で修正・再レビューして、最新 HEAD を APPROVED または CHANGES_REQUESTED の状態に更新します。PR の merge は人間が行います。

**使用方法:** `/pr-review #N` または `/pr-review N`

> **責務境界:** このコマンドは `gh pr merge`、ブランチ削除、main への checkout、main の pull を実行しない。diff の取得とレビュー結果の GitHub 投稿は行わず、`/pr-review-exec` に委譲する。

---

## 定数

- `MAX_REVIEW_ROUNDS=3`
- reviewer の GitHub token は `AI_REVIEW_TOKEN` を優先し、未設定の場合のみ後方互換のため `CODEX_REVIEW_TOKEN` を使用する
- 一時ファイルは `/tmp/claude-code-kit/<session-id>/pr-review-<PR番号>/` 配下だけに作成する

## Step 0: 引数と実行 agent の判定

`$ARGUMENTS` から PR 番号を取得し、`#N` の `#` は除去する。番号がなければ使用方法を報告して終了する。

実装元 agent を以下で判定する:

```bash
if [ -n "${CODEX_THREAD_ID:-}" ] || [ -n "${CODEX_CI:-}" ]; then
  IMPLEMENTER_AGENT="codex"
  REVIEWER_AGENT="claude"
else
  IMPLEMENTER_AGENT="claude"
  REVIEWER_AGENT="codex"
fi
```

環境から判定できない場合やユーザーが明示した場合は、現在の agent を実装元として扱う。reviewer と実装元を同じ agent にしてはならない。

## Step 1: PR とワークスペースのゲート

```bash
gh pr view <PR番号> --json number,url,title,state,isDraft,author,headRefName,headRefOid,baseRefName
```

以下を満たさなければ何も変更せず FAILED で終了する:

- PR が存在し `OPEN` である
- draft ではない
- head/base branch と head SHA を取得できる
- detached HEAD ではない
- `git status --porcelain` が空である

PR branch にいない場合は `gh pr checkout <PR番号>` で切り替える。このチェックアウトは Step 4.5 の修正作業のためであり、reviewer のレビュー自体はローカルの working tree を使わない（Step 4.2 参照）。

## Step 2: reviewer identity のゲート

```bash
REVIEW_TOKEN="${AI_REVIEW_TOKEN:-${CODEX_REVIEW_TOKEN:-}}"
REVIEWER_LOGIN=$(GH_TOKEN="$REVIEW_TOKEN" gh api user --jq '.login')
```

以下の場合は FAILED で終了する:

- token が未設定または認証できない
- `REVIEWER_LOGIN` が PR author と同じ
- reviewer token に PR review の投稿権限がない

token の値は表示・ファイル保存・ログ出力しない。この Step で確認した `REVIEW_TOKEN` / `REVIEWER_LOGIN` は以降の全ラウンドで使い回す（ラウンドごとに再確認しない）。

## Step 3: セッション一時ディレクトリ

`current-session-approved-path` から session ID を取得する。取得できない場合は現在の agent の session ID を使用する。それも取得できなければ、安全な一意 ID を生成する。

```bash
SESSION_TMP_DIR="/tmp/claude-code-kit/${SESSION_ID}/pr-review-<PR番号>"
mkdir -p "$SESSION_TMP_DIR"
```

reviewer subprocess の起動ログ・出力だけをこのディレクトリに保存する。diff ファイルや SHA 記録は生成しない（reviewer 自身が `gh pr diff` で取得するため不要）。

## Step 4: review loop

`ROUND=1` から `MAX_REVIEW_ROUNDS=3` まで繰り返す。

### 4.1 投稿済み review の起点を記録

reviewer subprocess を起動する前に、現在の `REVIEWER_LOGIN` による最新 review の ID（存在すれば）を記録する:

```bash
gh pr view <PR番号> --json reviews \
  --jq '[.reviews[] | select(.author.login == "'"$REVIEWER_LOGIN"'")] | last | .id // "none"'
```

この値を `PREV_REVIEW_ID` として保持する（4.3 で新規投稿の検出に使う）。

### 4.2 別 agent による review 実行

実装元が Claude の場合、reviewer（Codex）をリポジトリ外の scratch ディレクトリで実行する。Codex の `workspace-write` サンドボックスは cwd 配下だけを書き込み可能にするため、scratch ディレクトリを cwd にすることでリポジトリへの書き込み経路を作らずに `gh` のネットワークアクセスだけを許可する:

```bash
SCRATCH_DIR="$SESSION_TMP_DIR/round-${ROUND}-scratch"
mkdir -p "$SCRATCH_DIR"
REPO_ROOT="$(git rev-parse --show-toplevel)"

REVIEW_TOKEN="$REVIEW_TOKEN" codex exec \
  --sandbox workspace-write \
  -c sandbox_workspace_write.network_access=true \
  --ephemeral \
  --skip-git-repo-check \
  --cd "$SCRATCH_DIR" \
  --output-last-message "$SESSION_TMP_DIR/round-${ROUND}-review.txt" \
  "${REPO_ROOT}/commands/pr-review-exec.md を読み、そこに書かれている内容を PR #<PR番号> に対してそのまま実行しなさい。REVIEW_TOKEN は環境変数から利用できる。このタスク以外のコマンド（/work, /pr-review, /task, /patch 等）は実行しないこと。"
```

実装元が Codex の場合、reviewer（Claude）をこのリポジトリ内で、ツール権限を絞って実行する。Claude には OS レベルの sandbox がないため、`Edit`/`Write` を与えず `Bash` を `gh` の特定サブコマンドだけに制限することで同じ安全境界を作る:

```bash
REVIEW_TOKEN="$REVIEW_TOKEN" claude -p \
  --permission-mode dontAsk \
  --tools "Read,Bash" \
  --allowedTools "Read,Bash(gh pr diff *),Bash(gh pr view *),Bash(gh pr review *),Bash(gh api user *)" \
  "commands/pr-review-exec.md を読み、そこに書かれている内容を PR #<PR番号> に対してそのまま実行しなさい。REVIEW_TOKEN は環境変数から利用できる。このタスク以外のコマンド（/work, /pr-review, /task, /patch 等）は実行しないこと。" \
  > "$SESSION_TMP_DIR/round-${ROUND}-review.txt"
```

reviewer subprocess に Edit、Write、ファイル書き込み経路を与えない。GitHub への書き込みは `pr-review-exec.md` の指示に従い reviewer 自身が行う（`REVIEW_TOKEN` を用いた `gh pr review` の実行）。

### 4.3 投稿結果の確認

```bash
gh pr view <PR番号> --json reviews,headRefOid \
  --jq '[.reviews[] | select(.author.login == "'"$REVIEWER_LOGIN"'")] | last'
```

- 取得した最新 review の `id` が `PREV_REVIEW_ID` と同じ（新規投稿がない）場合: reviewer が review を投稿できなかったとみなし `FAILED` で終了する
- 新規投稿がある場合: その review の `state`（`APPROVED` / `CHANGES_REQUESTED`）と `commitId` を確認する
    - `commitId` が現在の `headRefOid` と一致しない場合: 古い commit に対する review とみなし `FAILED` で終了する

### 4.4 APPROVED の場合

review の `author.login` が `REVIEWER_LOGIN` であり、`state` が `APPROVED` であり、`commitId` が現在の `headRefOid` と一致することを確認できれば `APPROVED` で終了する。PR URL、reviewer、reviewed HEAD SHA を報告し、人間が merge するよう案内する。

### 4.5 REQUEST_CHANGES の場合: 指摘の検証と修正

review 本文（`gh pr view <PR番号> --json reviews` で取得できる該当 review の `body`）を実装元が読み、各指摘と該当ファイルを直接読んで事実に基づいて妥当性を判定する。

- suggestion は任意対応とし、blocking な指摘の解消を優先する
- 妥当で承認済みのファイル・ツール範囲内なら修正する
- session-approved 外のファイル、設計スコープ拡大、破壊的操作、秘密情報、権限追加が必要なら修正せず `CHANGES_REQUESTED` で終了する
- 指摘が誤りなら根拠を PR comment として投稿し、次ラウンドで reviewer が読む context に含める
- `ROUND == MAX_REVIEW_ROUNDS` の場合は追加修正を行わず `CHANGES_REQUESTED` で終了する

修正した場合:

1. 対象 repo の検証コマンドを実行する
2. `/git-commit` を実行する。PR/commit から issue 番号を取得できれば使用し、取得できなければ `issue_number=none` とする
3. 公開仕様や docs との整合性が変わる場合は `/docs-sync` を実行する
4. `git push` を実行する（force push 禁止）
5. workspace が clean であることを確認して次ラウンドへ進む

## Step 5: 終了状態

必ず次のいずれかを報告する:

- `APPROVED`: 最新 HEAD が別 agent / 別 GitHub account に承認された
- `CHANGES_REQUESTED`: blocking な指摘、スコープ超過、または最大ラウンド到達により人間判断が必要
- `FAILED`: gate、認証、GitHub API、reviewer の review 投稿、テスト、commit、push のいずれかが失敗

どの終了状態でも PR の merge、close、branch 削除、main checkout、main pull は実行しない。
