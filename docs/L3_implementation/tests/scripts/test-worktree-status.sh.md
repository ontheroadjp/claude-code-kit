# `tests/scripts/test-worktree-status.sh`

## 目的・役割

`scripts/worktree-status.sh` が manifest 記録済み symlink だけを除外し、実際の差分と通常 worktree の status を保持することを functional に検証する。

根拠: `tests/scripts/test-worktree-status.sh:1-91`

## 動作の概要

一時 directory 内に source repository と `.claude/worktrees/` 配下の fixture repository を作る。fixture には manifest 記録済みの top-level symlink、nested manifest entry の親 directory、real untracked file、tracked modification を用意する。Codex session-paths stub と manifest を置いて helper を実行し、symlink 系は出ず real changes は残ることを確認する。通常 path の repository では untracked status がそのまま返ることも確認する。

根拠: `tests/scripts/test-worktree-status.sh:32-89`

## 統合ポイント

- 対象: `scripts/worktree-status.sh`
- 実行: `bash tests/scripts/test-worktree-status.sh`

## 注意事項・既知の制限

fixture は session-paths の session ID 解決を検証せず、固定の tmp directory を返す最小 stub を使う。
