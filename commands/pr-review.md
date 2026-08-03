# /pr-review

指定した PR を実装元とは別の AI agent でレビューし、妥当な指摘を承認済みスコープ内で修正・再レビューして、最新 HEAD を APPROVED または CHANGES_REQUESTED の状態に更新します。PR の merge は人間が行います。

**使用方法:** `/pr-review #N` または `/pr-review N`

> **責務境界:** このコマンドは `gh pr merge`、ブランチ削除、main への checkout、main の pull を実行しない。

---

## 定数

- `MAX_REVIEW_ROUNDS=3`
- `TRIVIAL_FIX_MAX_LINES=5`（1 finding あたりの修正行数がこの値以下かつ機械的な修正のみの場合に trivial round と分類する）
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

PR branch にいない場合は `gh pr checkout <PR番号>` で切り替える。`git fetch origin <baseRefName> <headRefName>` を実行し、local HEAD と `headRefOid` が一致することを確認する。fast-forward で一致させられない場合は停止する。stash、reset、rebase、force push は行わない。

## Step 2: reviewer identity のゲート

```bash
REVIEW_TOKEN="${AI_REVIEW_TOKEN:-${CODEX_REVIEW_TOKEN:-}}"
REVIEWER_LOGIN=$(GH_TOKEN="$REVIEW_TOKEN" gh api user --jq '.login')
```

以下の場合は FAILED で終了する:

- token が未設定または認証できない
- `REVIEWER_LOGIN` が PR author と同じ
- reviewer token に PR review の投稿権限がない

token の値は表示・ファイル保存・ログ出力しない。

## Step 3: セッション一時ディレクトリ

`current-session-approved-path` から session ID を取得する。取得できない場合は現在の agent の session ID を使用する。それも取得できなければ、安全な一意 ID を生成する。

```bash
SESSION_TMP_DIR="/tmp/claude-code-kit/${SESSION_ID}/pr-review-<PR番号>"
mkdir -p "$SESSION_TMP_DIR"
```

各ラウンドの diff、review 出力、元 agent の判断はこのディレクトリだけに保存する。

## Step 4: review loop

`ROUND=1` から `MAX_REVIEW_ROUNDS=3` まで繰り返す。

### 4.1 review 対象の固定

各ラウンド開始時に最初に base branch を更新する:

```bash
git fetch origin "<baseRefName>"
```

fetch に失敗した場合は stale な base から review context を生成・投稿せず、`FAILED` で終了する。fetch 成功後に GitHub から最新の `headRefOid` を再取得し、local HEAD と一致させる。次を一時ファイルへ保存する:

```bash
git diff --find-renames "origin/<baseRefName>...HEAD" > "$SESSION_TMP_DIR/round-${ROUND}.diff"
gh pr view <PR番号> --json title,body,comments,reviews > "$SESSION_TMP_DIR/round-${ROUND}-context.json"
```

`ROUND == 1` の場合、reviewer には `round-${ROUND}.diff`（PR 全体の diff）をそのまま渡す。

`ROUND >= 2` の場合、直前ラウンドの `$SESSION_TMP_DIR/round-$((ROUND-1))-review.txt` から `REVIEWED_HEAD_SHA:` の値を `PREV_REVIEWED_SHA` として取得し、追加で増分 diff を生成する:

```bash
git diff --find-renames "${PREV_REVIEWED_SHA}..HEAD" > "$SESSION_TMP_DIR/round-${ROUND}-incremental.diff"
```

`PREV_REVIEWED_SHA` が取得できない場合（前ラウンドの出力が所定形式でない等）は増分 diff を生成せず、`round-${ROUND}.diff`（PR 全体の diff）を reviewer に渡す通常モードにフォールバックする。取得できた場合、reviewer には `round-${ROUND}-incremental.diff` と直前ラウンドの `FINDINGS` 一覧を渡す（このモードの適用可否とプロンプトの分岐は 4.2 を参照）。

reviewer には以下を必ず要求する:

- repo の `AGENTS.md` / `CLAUDE.md` と diff を根拠にレビューする
- ファイルを編集せず、read-only sandbox 内の読み取り操作だけを使用する
- 日本語で回答する
- blocking finding のみ `REQUEST_CHANGES` とする
- `ROUND >= 2` かつ増分 diff モードの場合は、直前ラウンドで指摘した blocking finding が渡された増分 diff で解消されているかを判定基準に含める
- 末尾に次の機械判定可能な形式を必ず出力する

```text
VERDICT: APPROVE | REQUEST_CHANGES
REVIEWED_HEAD_SHA: <40-character SHA>
FINDINGS:
- [blocking|suggestion] <path>:<line> <finding>
```

finding がない場合は `FINDINGS: none` とする。

### 4.2 別 agent による review

`$SESSION_TMP_DIR/round-$((ROUND-1))-trivial.flag` が存在し内容が `true` の場合、このラウンドは **confirm-only モード**とする。reviewer への指示（review instructions）を「直前ラウンドの blocking finding 一覧と 4.1 で生成した増分 diff（`round-${ROUND}-incremental.diff`）だけを根拠に、指摘が解消されたか・増分 diff 内に新たな blocking finding がないかだけを判定する」に限定し、PR 全体の設計方針の再評価は求めない。フラグが存在しない場合、または `ROUND == 1` の場合は通常モード（PR 全体 diff に基づくフルレビュー）とする。

confirm-only モードでも別 agent の起動・書き込み権限の禁止（read-only sandbox / `Read` ツール限定）・機械判定契約（`VERDICT` / `REVIEWED_HEAD_SHA` / `FINDINGS`）は通常モードと同一とする。**APPROVE の可否は必ずこのラウンドの別 agent 起動結果に基づく — confirm-only モードであっても別 agent の起動自体を省略しない。**

実装元が Claude の場合は Codex を実行する:

```bash
codex exec \
  --sandbox read-only \
  --ephemeral \
  --cd "$(git rev-parse --show-toplevel)" \
  --output-last-message "$SESSION_TMP_DIR/round-${ROUND}-review.txt" \
  "<review instructions including paths to the diff/context files, fixed HEAD SHA, and output contract>"
```

実装元が Codex の場合は Claude を Read-only で実行する:

```bash
claude -p \
  --add-dir "$SESSION_TMP_DIR" \
  --permission-mode dontAsk \
  --tools "Read" \
  --allowedTools "Read" \
  "<review instructions including paths to the diff/context files, fixed HEAD SHA, and output contract>" \
  > "$SESSION_TMP_DIR/round-${ROUND}-review.txt"
```

reviewer subprocess に Edit、Write、GitHub 書き込み権限を与えない。Codex は `--sandbox read-only` で repo と session temp を読み取り、`--output-last-message` で機械判定対象の最終回答だけを保存する。Claude の `--add-dir` は review context がある session temp の Read 許可にだけ使用する。CLI 失敗、空出力、形式不正、`REVIEWED_HEAD_SHA` 不一致の場合は GitHub review を投稿せず FAILED で終了する。

### 4.3 GitHub review の投稿

投稿直前に `headRefOid` を再取得する。4.1 で固定した SHA から変化していた場合、その review は投稿せず次ラウンドで最新 HEAD をレビューする。

APPROVE の場合:

```bash
GH_TOKEN="$REVIEW_TOKEN" gh pr review <PR番号> --approve \
  --body-file "$SESSION_TMP_DIR/round-${ROUND}-review.txt"
```

REQUEST_CHANGES の場合:

```bash
GH_TOKEN="$REVIEW_TOKEN" gh pr review <PR番号> --request-changes \
  --body-file "$SESSION_TMP_DIR/round-${ROUND}-review.txt"
```

投稿失敗時は FAILED で終了する。

### 4.4 APPROVED の検証と終了

APPROVE を投稿した場合、GitHub API から review を再取得し、次を全て確認する:

- reviewer が `REVIEWER_LOGIN`
- state が `APPROVED`
- review の `commit_id` が固定した HEAD SHA と一致
- 現在の `headRefOid` も同じ SHA

全て満たせば APPROVED で終了する。PR URL、reviewer、reviewed HEAD SHA を報告し、人間が merge するよう案内する。

### 4.5 指摘の検証と修正

REQUEST_CHANGES の場合、元 agent が各 finding と該当ファイルを直接読み、事実に基づいて妥当性を判定する。

- suggestion は任意対応とし、blocking finding の解消を優先する
- 妥当で承認済みのファイル・ツール範囲内なら修正する
- session-approved 外のファイル、設計スコープ拡大、破壊的操作、秘密情報、権限追加が必要なら修正せず CHANGES_REQUESTED で終了する
- 指摘が誤りなら根拠を PR comment として投稿し、次ラウンドの context に含める
- `ROUND == MAX_REVIEW_ROUNDS` の場合は追加修正を行わず CHANGES_REQUESTED で終了する

修正した場合:

1. 対象 repo の検証コマンドを実行する
2. `/git-commit` を実行する。PR/commit から issue 番号を取得できれば使用し、取得できなければ `issue_number=none` とする
3. 公開仕様や docs との整合性が変わる場合は `/docs-sync` を実行する
4. `git push` を実行する（force push 禁止）
5. このラウンドで適用した修正が全て次を満たす場合、trivial round と分類し `$SESSION_TMP_DIR/round-${ROUND}-trivial.flag` に `true` を書き込む。1件でも満たさない場合はこのファイルを作成しない（前ラウンドのフラグが残っていれば削除する）:
    - 修正対象が session-approved 内のみ
    - finding 1件あたりの diff 行数（追加+削除の合計）が `TRIVIAL_FIX_MAX_LINES` 以下
    - typo・コメント・文言・単純な値修正など、ロジックを変更しない機械的な修正である
6. workspace が clean であることを確認して次ラウンドへ進む

## Step 5: 終了状態

必ず次のいずれかを報告する:

- `APPROVED`: 最新 HEAD が別 agent / 別 GitHub account に承認された
- `CHANGES_REQUESTED`: blocking finding、スコープ超過、または最大ラウンド到達により人間判断が必要
- `FAILED`: CLI、認証、GitHub API、形式、テスト、commit、push のいずれかが失敗

どの終了状態でも PR の merge、close、branch 削除、main checkout、main pull は実行しない。
