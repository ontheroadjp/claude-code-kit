# /git-pr

PR 作成を担うスラッシュコマンド。`commands/*.md` から `/git-pr` として呼び出されます。

セッション temp ディレクトリに `/task` と `/docs-sync` が書き出したファイルを参照し、`git push` → `gh pr create` を実行します。

template 参照時の `TEMPLATES_DIR` は実行 agent に応じて決定する:
- Claude Code: `~/.claude/templates`
- Codex CLI: `~/.codex/templates`

## 前提ゲート

- main ブランチ以外にいること
- `git log main..HEAD --oneline` の出力が 1 件以上あること（push するコミットが存在すること）

## ワークフロー

### Step 1: セッション temp ディレクトリの特定

セッション ID は `$CLAUDE_CODE_SESSION_ID`（Codex は `$CODEX_THREAD_ID` のハッシュ）から直接解決する:

```bash
SESSION_ID="${CLAUDE_CODE_KIT_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-}}"
if [ -z "$SESSION_ID" ] && [ -n "${CODEX_THREAD_ID:-}" ]; then
    SESSION_ID="codex-$(printf '%s' "$CODEX_THREAD_ID" | sha256sum | cut -c1-16)"
fi
SESSION_ID="$(printf '%s' "$SESSION_ID" | tr -c 'A-Za-z0-9._-' '_')"
SESSION_TMP_DIR="/tmp/claude-code-kit/${SESSION_ID}"
```

- セッション ID が特定できない場合: temp ファイルなしとして Step 2 へ進む

### Step 2: PR タイトルの準備

- `${SESSION_TMP_DIR}/pr-title.txt` が存在する場合: その内容（1 行）を PR タイトルとして使用する
- 存在しない場合: `git log main...HEAD --oneline` から英語でタイトルを生成する

### Step 3: PR body の準備

- `${SESSION_TMP_DIR}/pr-body.md` が存在する場合: その内容を PR 本文として使用する
- 存在しない場合:
    - `${TEMPLATES_DIR}/pr.md` が存在する場合: `git diff main...HEAD` の内容をもとにテンプレートを埋めて PR 本文を生成する
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
- `/git-pr` の責務はここで完結する。以降の review・merge は自動実行せず、人間（または `/review-resolve`・`/codex-review` 等の別コマンドを手動起動するユーザー）が行う
