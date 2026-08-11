# hooks/lib/README.md — L3 per-file doc

## 目的・役割

`hooks/lib/` ディレクトリの役割と `session-id.sh`・`session-paths.sh`・`approval-safety.sh` の使い方を開発者向けに説明するドキュメント。

## 動作の概要

- ファイル一覧表（`approval-safety.sh`・`session-id.sh`・`session-paths.sh`）
- `approval-safety.sh` が提供する `approval_safety_destructive_reason` 関数のシグネチャと検出対象を表で示す
- `session-id.sh` の `session_id_resolve` の使い方、および `commands/*.md` が `source` せず `session-paths.sh` 経由で使う理由（issue #316）
- `session-paths.sh` のモード（`session-approved`/`session-tmp-dir`）と `commands/*.md` からの呼び出し例をコードスニペットで説明

## 重要な設計判断

- 破壊的操作の判定リストは `hooks/lib/approval-safety.sh` が正となり、README はその一覧を人間可読な形で転記する
- README が `approval-safety.sh`/`session-id.sh`/`session-paths.sh` の仕様と乖離しないよう、これらを変更した際は本ファイルも更新すること
- `session-paths.sh` を追加した理由（`commands/*.md` のインライン展開が worktree 隔離セッションで harness に拒否される問題）は `docs/L3_implementation/hooks/lib/session-paths.sh.md` に詳細を記録し、本 README は要約のみを持つ

## 統合ポイント

- 参照元: `hooks/auto-approve-readonly.sh`、`hooks/guard-destructive-cmd.sh`、`hooks/cleanup-session.sh`（実際に source する）、`hooks/lib/session-paths.sh`（`session-id.sh` を source する）
- 参照元（直接実行）: `commands/task.md`・`patch.md`・`review-resolve.md`・`docs-sync.md`・`git-pr.md`・`triage-issues-for-auto-approve.md`（`session-paths.sh` を `bash` で直接実行）
- 関連: `docs/L3_implementation/hooks/auto_approve_readonly.md`、`docs/L3_implementation/hooks/lib/session-id.sh.md`、`docs/L3_implementation/hooks/lib/session-paths.sh.md`

根拠: `hooks/lib/README.md:1-55`, `hooks/lib/approval-safety.sh:1-87`

## 変更履歴（git log より自動生成）

- db6d6c3 fix(#210): resolve session id from env instead of a shared pointer file
- 3656e6e docs(#175): add README.md to each module directory
