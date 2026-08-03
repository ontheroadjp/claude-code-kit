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

### commands/*.md では `source` せずインライン展開する理由

`commands/*.md` の Bash スニペットは、この repo ではなくユーザーの任意のプロジェクトディレクトリで実行される。`hooks/auto-approve-readonly.sh` は自分自身の symlink を `readlink` してこの repo の場所を解決できるが（`BASH_SOURCE[0]` 経由）、markdown 埋め込みの Bash スニペットにはその仕組みがなく、任意の作業ディレクトリからこの repo の `hooks/lib/session-id.sh` を確実に `source` する手段がない（`readlink -f` は macOS 標準の BSD readlink では利用できない等、環境依存の脆さもある）。そのため、同じ解決式をコマンド側に短くインライン展開する方式を採用した。式を変更する場合は両方（このファイルと各 `commands/*.md`）を更新する必要がある。

## 統合ポイント

- 呼び出し元: `hooks/auto-approve-readonly.sh`、`hooks/cleanup-session.sh`（いずれも `source` して使用）
- 参照（インライン展開、`source` はしない）: `commands/work.md`、`commands/task.md`、`commands/patch.md`、`commands/docs-sync.md`、`commands/git-pr.md`
- 呼び出すもの: なし（外部コマンドなし。`sha256sum`/`cksum` に依存）

## 注意事項

- `payload` 引数を省略した場合、hook 専用の優先順位（3・4）はスキップされる
- `process-<PPID>` フォールバックは hook プロセスとコマンド実行シェルで PPID が異なるため、両者で一致しない。呼び出し側はこのケースを「未解決」として扱い、`session-approved`/`SESSION_TMP_DIR` の読み書きをスキップする設計になっている

## 変更履歴（git log より自動生成）

- db6d6c3 fix(#210): resolve session id from env instead of a shared pointer file
