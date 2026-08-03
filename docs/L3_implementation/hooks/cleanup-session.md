# hooks/cleanup-session.sh specification

## 目的・役割

`hooks/cleanup-session.sh` は Stop hook として登録されるスクリプトで、セッション終了時に `session-approved` ファイルを削除する。

Stop hook は Claude が出力を返すたびに（ターン終了ごとに）発火する。セッション全体の終了のみを検知するわけではない。

根拠: `hooks/cleanup-session.sh:1-2`

## 動作の概要

1. `resolve_session_id()` でセッション ID を導出する
2. 対応する `session-approved` ファイルを削除する
3. 空になった session ディレクトリを `rmdir`（内容があれば何もしない）

SESSION_TMP_DIR（`/tmp/claude-code-kit/<SESSION_ID>/`）は削除しない。`/tmp` の自動クリーンアップ（OS 再起動 / Linux の tmpfiles.d、通常10日）に委ねる。

根拠: `hooks/cleanup-session.sh:39-50`

## SESSION_ID 導出ロジック

`hooks/lib/session-id.sh` の `session_id_resolve`（`hooks/auto-approve-readonly.sh` と共有）を `source` して使う。優先順位:

```
1. CLAUDE_CODE_KIT_SESSION_ID 環境変数
2. CLAUDE_CODE_SESSION_ID 環境変数（Claude Code のセッション ID）
3. payload JSON の session_id（Claude Code が UUID で提供）
4. transcript_path の sha256sum 先16文字
5. CODEX_THREAD_ID の sha256sum 先16文字
6. fallback: process-${PPID:-$$}（弱い。session-approved を書かない）
```

詳細は `docs/L3_implementation/hooks/lib/session-id.sh.md` を参照。

根拠: `hooks/cleanup-session.sh:7-16`, `hooks/lib/session-id.sh`

## 重要な設計判断

### SESSION_TMP_DIR を Stop hook で削除しない理由

Stop hook はターン終了ごとに発火するため、`/task` → `/docs-sync` → `/git-pr` のようにスキルをまたいで実行する場合、スキル間で Stop hook が走り SESSION_TMP_DIR を削除してしまう。SESSION_TMP_DIR はスキル間の一時的なデータ受け渡し（`pr-body.md`, `pr-title.txt`, `pr-docs-sync-result.md`）に使われるため、Stop hook での削除は不適切。

`/tmp` は OS 再起動時に自動削除される。Linux では `tmpfiles.d` により通常10日以内にクリーンアップされる。SESSION_ID は Claude Code が提供する UUID（会話ごとに一意）のため、複数セッションの temp ファイルが混在しても別 SESSION_ID のディレクトリに分離されており、誤読のリスクは無視できる。

### session-approved を削除する理由

`session-approved` には `/work` フローで承認されたツールカテゴリとファイルパスが記録される。セッション終了後も残すと、次の `/work` 呼び出し前に前セッションの承認状態が残存し、意図しないツール自動承認が起きる可能性がある。G-0 ゲートでも削除するが、Stop hook でも削除することで確実にクリアする。

## 統合ポイント

- 呼び出し元: Claude Code / Codex CLI の Stop hook として登録（`~/.claude/hooks/` または `~/.codex/hooks/`）
- 呼び出すもの: なし（外部コマンドなし）
- 関連ファイル: `session-approved`（`~/.local/state/claude-code-kit/sessions/<SESSION_ID>/session-approved`）
- SESSION_TMP_DIR: `/tmp/claude-code-kit/<SESSION_ID>/`（削除しない）

## 注意事項

- Stop hook はターン終了ごとに発火する（セッション終了専用ではない）
- fallback (`process-${PPID}`) の場合、`session-approved` も削除対象にならない（スキップ扱い）
- `rmdir` は空ディレクトリのみ削除。sessions ディレクトリに他のセッションのファイルが残っていれば失敗するが、`|| true` で無視する
- issue #210 により `${STATE_ROOT}/current-session-approved-path`（グローバル共有ポインタファイル）への書き込みは廃止された。詳細は `docs/L3_implementation/hooks/auto_approve_readonly.md` の「グローバル共有ポインタファイルの廃止」を参照

## 変更履歴（git log より自動生成）

- 780f8c3 fix(#169): remove SESSION_TMP_DIR cleanup from Stop hook
- 4e96f9c feat(#142): add session-scoped temp hook access
- 677e75b fix: use CODEX_THREAD_ID for session identity and disable session-approved in PPID fallback
- dd29feb feat(#129): store session approvals per session
- 83374dc feat(#108): add session-based approval to eliminate double-confirmation prompts
