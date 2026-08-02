# /git-pr

PR 作成を担うスラッシュコマンド。`commands/*.md` から `/git-pr` として呼び出されます。

セッション temp ディレクトリに `/task` と `/docs-sync` が書き出したファイルを参照し、`git push` → `gh pr create` を実行します。

## 前提ゲート

- main ブランチ以外にいること
- `git log main..HEAD --oneline` の出力が 1 件以上あること（push するコミットが存在すること）

## ワークフロー

### Step 1: セッション temp ディレクトリの特定

```bash
APPROVED_PATH=$(cat "${XDG_STATE_HOME:-$HOME/.local/state}/claude-code-kit/current-session-approved-path" 2>/dev/null)
SESSION_ID=$(basename "$(dirname "$APPROVED_PATH")" 2>/dev/null)
SESSION_TMP_DIR="/tmp/claude-code-kit/${SESSION_ID}"
```

- パスが特定できない場合: temp ファイルなしとして Step 2 へ進む

### Step 2: PR タイトルの準備

- `${SESSION_TMP_DIR}/pr-title.txt` が存在する場合: その内容（1 行）を PR タイトルとして使用する
- 存在しない場合: `git log main...HEAD --oneline` から英語でタイトルを生成する

### Step 3: PR body の準備

- `${SESSION_TMP_DIR}/pr-body.md` が存在する場合: その内容を PR 本文として使用する
- 存在しない場合:
    - `~/.config/claude-code-kit/templates/pr.md` が存在する場合: `git diff main...HEAD` の内容をもとにテンプレートを埋めて PR 本文を生成する
    - テンプレートが存在しない場合: `git diff main...HEAD` から最小限の本文を生成する

### Step 4: docs sync 結果の追記

- `${SESSION_TMP_DIR}/pr-docs-sync-result.md` が存在する場合: PR 本文末尾に追記する
- 存在しない場合: スキップ

### Step 5: git push

```bash
git push -u origin HEAD
```

### Step 6: PR 作成

- PR タイトル・本文は英語で記述する
- `gh pr create` で PR を ready for review として作成する:

```bash
gh pr create --title "<title>" --body-file - <<'EOF'
[PR 本文]
EOF
```

### Step 7: 結果報告

- PR URL を報告する

### Step 8: /pr-review への引き継ぎ

Step 6 で PR の作成に成功した場合のみ、作成した PR 番号を取得する:

```bash
PR_NUMBER=$(gh pr view --json number --jq '.number')
```

- PR 番号を取得できた場合: ユーザー確認なしで `/pr-review #${PR_NUMBER}` を自動実行する
- PR 番号を取得できない場合: PR URL と「PR 番号を取得できなかったため /pr-review を開始できませんでした」を報告して終了する
- `/pr-review` が APPROVED 以外で終了しても、作成済み PR を close・merge・削除しない
- Step 1〜7 の push・PR 作成・結果報告の振る舞いは変更しない
