# hooks/cleanup-session.sh specification

## 目的・役割

`hooks/cleanup-session.sh` は Stop hook として登録されるスクリプトで、ターン終了時に `session-approved` ファイルを削除する。

Stop hook は Claude が出力を返すたびに（ターン終了ごとに）発火する。セッション全体の終了のみを検知するわけではない。

根拠: `hooks/cleanup-session.sh:1-2`

## 動作の概要

1. 共有 helper の `session_id_resolve()` でセッション ID を導出する
2. 対応する `session-approved` ファイルを削除する
3. 空になった session ディレクトリを `rmdir`（内容があれば何もしない）

SESSION_TMP_DIR（`/tmp/claude-code-kit/<SESSION_ID>/`）は削除しない。保持期間と削除時期は host OS の `/tmp` policy に委ねる。

根拠: `hooks/cleanup-session.sh:15-24`

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

`cleanup-session.sh` 自体は SESSION_TMP_DIR を削除しない。host OS が実際にいつ削除するかは repository から確定できず、OS の `/tmp` policy を確認する必要がある。session ID ごとに directory を分離する仕様は `commands/task.md` などの command workflow が担う。

### session-approved を削除する理由

`session-approved` には `/work` フローで承認されたツールカテゴリとファイルパスが記録される。ターン終了後も残すと後続ターンへ承認状態が残存するため、Stop hook が削除する。`commands/work.md` の G-0 は issue #261 以降このファイルへ触れず、通常時は Stop hook による absent 状態を前提とする。

## 統合ポイント

- 呼び出し元: Claude Code / Codex CLI の Stop hook として登録（`~/.claude/hooks/` または `~/.codex/hooks/`）
- 呼び出すもの: `hooks/lib/session-id.sh` と標準 shell utilities（payload 解釈では helper 経由で `jq` を利用）
- 関連ファイル: `session-approved`（`~/.local/state/claude-code-kit/sessions/<SESSION_ID>/session-approved`）
- SESSION_TMP_DIR: `/tmp/claude-code-kit/<SESSION_ID>/`（削除しない）

## 注意事項

- Stop hook はターン終了ごとに発火する（セッション終了専用ではない）
- fallback (`process-${PPID}`) は弱い識別子であり、対応する process-scoped path が削除対象になる
- `rmdir` は空ディレクトリのみ削除。sessions ディレクトリに他のセッションのファイルが残っていれば失敗するが、`|| true` で無視する
- issue #210 により `${STATE_ROOT}/current-session-approved-path`（グローバル共有ポインタファイル）への書き込みは廃止された。詳細は `docs/L3_implementation/hooks/auto_approve_readonly.md` の「グローバル共有ポインタファイルの廃止」を参照

## 変更履歴（git log より自動生成）

- 780f8c3 fix(#169): remove SESSION_TMP_DIR cleanup from Stop hook
- 4e96f9c feat(#142): add session-scoped temp hook access
- 677e75b fix: use CODEX_THREAD_ID for session identity and disable session-approved in PPID fallback
- dd29feb feat(#129): store session approvals per session
- 83374dc feat(#108): add session-based approval to eliminate double-confirmation prompts
