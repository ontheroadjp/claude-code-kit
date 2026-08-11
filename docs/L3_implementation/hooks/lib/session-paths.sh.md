# hooks/lib/session-paths.sh specification

## 目的・役割

`hooks/lib/session-paths.sh` は `commands/*.md`（`/task`・`/patch`・`/review-resolve`・`/docs-sync`・`/git-pr`・`/triage-issues-for-auto-approve`）が session-approved ファイルおよび SESSION_TMP_DIR の絶対パスを取得するための直接実行 CLI である。`hooks/lib/session-id.sh` の `session_id_resolve` を内部で再利用する。

根拠: `hooks/lib/session-paths.sh:1-35`, issue #316

## 動作の概要

`bash <path>/session-paths.sh <mode>` として実行する（`source` はしない）。自分自身の symlink を `readlink` してこの repo 内の実体ディレクトリを解決し、同じディレクトリの `session-id.sh` を `source` する。`mode` に応じて標準出力へ絶対パスを1行返す:

- `session-approved`: `hooks/cleanup-session.sh`/`hooks/auto-approve-readonly.sh` と同一の formula（`CLAUDE_CODE_KIT_SESSION_APPROVED_FILE` → `CLAUDE_CODE_KIT_SESSION_DIR` → `CLAUDE_CODE_KIT_STATE_HOME`/`XDG_STATE_HOME` の順にオーバーライドを尊重）で session-approved ファイルの絶対パスを返す
- `session-tmp-dir`: `CLAUDE_CODE_KIT_TMP_ROOT`（既定 `/tmp/claude-code-kit`）配下のセッション temp ディレクトリの絶対パスを返す
- それ以外（引数なし・不明な引数）: 使い方を stderr に出力して exit 1

根拠: `hooks/lib/session-paths.sh:11-35`

## 重要な設計判断

### 直接実行の CLI として設計した理由（issue #316）

以前は `commands/*.md` の8箇所（6ファイル）が `session_id_resolve` と同じ解決式を Bash スニペットとしてインライン展開していた。この式は brace expansion（`${VAR}`）と代入への command substitution（`$(...)`）を含んでおり、`/work-multi` の worktree 隔離セッションでは Claude Code harness の worktree 隔離ガードが「worktree の外に影響しないことを静的に検証できない」としてコマンド自体を拒否していた（harness 側の一般的な安全策であり、この repo の hooks とは独立）。

対策として、解決ロジックを1つのスクリプトに集約し、`commands/*.md` 側は `bash ~/.claude/hooks/lib/session-paths.sh <mode>`（Codex: `~/.codex/...`）という brace expansion も代入への command substitution も含まない単一のプレーンな呼び出しのみを埋め込む方式にした。出力された絶対パスは CLAUDE.md の resolve-then-embed 規約に従い、後続の Bash 呼び出しへリテラル文字列として埋め込む。

### `session-tmp-dir` にもオーバーライド（`CLAUDE_CODE_KIT_TMP_ROOT`）を追加した理由

`hooks/auto-approve-readonly.sh` は `SESSION_TMP_ROOT="${CLAUDE_CODE_KIT_TMP_ROOT:-/tmp/claude-code-kit}"` というオーバーライドを既に持っていたが、`commands/*.md` 側のインライン式は `/tmp/claude-code-kit/${SESSION_ID}` を固定でハードコードしており、このオーバーライドを無視するドリフトが生じていた。集約に合わせてこのドリフトも解消した。

### `hooks/auto-approve-readonly.sh`/`hooks/cleanup-session.sh` と同様の自己位置解決を使う理由

`session-paths.sh` は `~/.claude/hooks/lib/session-paths.sh` として symlink されて実行される。`BASH_SOURCE[0]` を `readlink` して実体の repo パスを得ることで、同じディレクトリに存在する `session-id.sh` を相対パスで確実に `source` できる（`session-id.sh` 自体を別途 symlink する必要はないが、`install.sh` は一貫性のため `hooks/lib/*.sh` を丸ごと symlink する）。

根拠: `hooks/lib/session-paths.sh:14-19`, `hooks/auto-approve-readonly.sh:33-47`, `hooks/cleanup-session.sh:7-13`

## 統合ポイント

- 呼び出し元: `commands/task.md`、`commands/patch.md`、`commands/review-resolve.md`、`commands/docs-sync.md`、`commands/git-pr.md`、`commands/triage-issues-for-auto-approve.md`（いずれも `bash <installed-path>/session-paths.sh <mode>` として直接実行）
- 呼び出すもの: `hooks/lib/session-id.sh`（`session_id_resolve` を `source` して利用）
- インストール: `install.sh` が `hooks/lib/*.sh` を `~/.claude/hooks/lib/` と `~/.codex/hooks/lib/` の両方へ symlink する

## 注意事項・既知の制限

- `session_id_resolve` に payload を渡さない（`commands/*.md` の Bash コンテキストには PreToolUse/Stop hook のペイロードが存在しないため、優先順位の 3・4 番目は常にスキップされる）
- セッション ID が解決できない場合でも `process-<PPID>` フォールバックにより何らかの値は返る点は `session-id.sh` と同じ。呼び出し側（`commands/*.md`）はコマンドの失敗（非ゼロ終了）のみを「未解決」として扱う設計になっている

## 変更履歴（git log より自動生成）

- e7d5698 fix(#316): resolve session paths via hooks/lib/session-paths.sh to survive worktree-isolated harness guard
