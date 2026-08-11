# hooks/lib/session-id.sh specification

## 目的・役割

`hooks/lib/session-id.sh` は `hooks/auto-approve-readonly.sh` と `hooks/cleanup-session.sh` が共有するセッション ID 解決ライブラリである。両ファイルに重複していた `sanitize_session_id` / `hash_session_key` / `resolve_session_id` を一本化する。

根拠: `hooks/lib/session-id.sh:1-38`

## 動作の概要

`session_id_resolve [payload]` が優先順位に従ってセッション ID を解決する:

1. `CLAUDE_CODE_KIT_SESSION_ID`（テスト/上書き用）
2. `CLAUDE_CODE_SESSION_ID`（Claude Code のセッション ID。hook プロセスだけでなく Bash tool が実行するシェルにも渡る）
3. `payload.session_id`（hook 文脈のみ。`payload` 引数を渡した場合）
4. `payload.transcript_path` のハッシュ（hook 文脈のみ）
5. `CODEX_THREAD_ID` のハッシュ
6. `process-<PPID>` フォールバック（弱い。呼び出し側は「未解決」として扱う）

`session_id_sanitize` は英数字・`.`・`_`・`-` 以外を `_` に置換する。`session_id_hash_key` は `sha256sum`（無ければ `cksum`）で先頭16文字のハッシュを作る。

根拠: `hooks/lib/session-id.sh:4-38`

## 重要な設計判断

### `CLAUDE_CODE_SESSION_ID` を優先順位に追加した理由（issue #210）

以前は `hooks/auto-approve-readonly.sh` が解決した `SESSION_ID` を `${STATE_ROOT}/current-session-approved-path` という**グローバル単一ファイル**に書き出し、`commands/work.md` / `task.md` / `patch.md` / `docs-sync.md` / `git-pr.md` がそれを読んで自分の `SESSION_ID` を逆算していた。複数セッションが同時に走ると、どちらか一方の hook 呼び出しが直近にそのファイルを上書きするため、他方のセッションが誤ったパスを読み取る競合が発生していた。

実機セッションで `$CLAUDE_CODE_SESSION_ID`（Bash tool 実行シェルの環境変数）が hook の解決結果（`payload.session_id` 由来）と完全一致することを確認できたため、コマンド側が共有ファイルを経由せず環境変数から直接セッション ID を得られるようにした。これにより `current-session-approved-path` への書き込みは不要になり、`hooks/auto-approve-readonly.sh` から完全に削除した。

### commands/*.md では `source` せず `hooks/lib/session-paths.sh` 経由で使う理由（issue #316 で変更）

`commands/*.md` の Bash スニペットは、この repo ではなくユーザーの任意のプロジェクトディレクトリで実行される。`hooks/auto-approve-readonly.sh` は自分自身の symlink を `readlink` してこの repo の場所を解決できるが（`BASH_SOURCE[0]` 経由）、markdown 埋め込みの Bash スニペットにはその仕組みがなく、任意の作業ディレクトリからこの repo の `hooks/lib/session-id.sh` を確実に `source` する手段がない（`readlink -f` は macOS 標準の BSD readlink では利用できない等、環境依存の脆さもある）。

以前はこの制約への対処として、`session_id_resolve` と同じ解決式（`CLAUDE_CODE_KIT_SESSION_ID` → `CLAUDE_CODE_SESSION_ID` → `CODEX_THREAD_ID` のハッシュ）を `commands/*.md` に短くインライン展開していた。しかしこの式自体が brace expansion（`${VAR}`）と代入への command substitution（`$(...)`）を含むため、`/work-multi` の worktree 隔離セッションでは Claude Code harness の worktree 隔離ガードにコマンドごと拒否されることが判明した（issue #316）。現在は `hooks/lib/session-paths.sh`（`session_id_resolve` を内部で `source` して再利用する直接実行 CLI）を新設し、`commands/*.md` は `bash ~/.claude/hooks/lib/session-paths.sh <mode>` という単一のプレーンな呼び出しのみを埋め込む。`session-id.sh` 自体は今も `source` されない（`source` するのは新設した `session-paths.sh` の役目）。

## 統合ポイント

- 呼び出し元: `hooks/auto-approve-readonly.sh`、`hooks/cleanup-session.sh`、`hooks/lib/session-paths.sh`（いずれも `source` して使用）
- 参照（`session-paths.sh` 経由の間接呼び出し、`source` はしない）: `commands/task.md`、`commands/patch.md`、`commands/review-resolve.md`、`commands/docs-sync.md`、`commands/git-pr.md`、`commands/triage-issues-for-auto-approve.md`
- 呼び出すもの: なし（外部コマンドなし。`sha256sum`/`cksum` に依存）

## 注意事項

- `payload` 引数を省略した場合、hook 専用の優先順位（3・4）はスキップされる
- `process-<PPID>` フォールバックは hook プロセスとコマンド実行シェルで PPID が異なるため、両者で一致しない。呼び出し側はこのケースを「未解決」として扱い、`session-approved`/`SESSION_TMP_DIR` の読み書きをスキップする設計になっている

## 変更履歴（git log より自動生成）

- db6d6c3 fix(#210): resolve session id from env instead of a shared pointer file
