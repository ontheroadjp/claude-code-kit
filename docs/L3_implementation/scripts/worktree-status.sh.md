# `scripts/worktree-status.sh`

## 目的・役割

worktree 隔離セッションの workspace status から、current session が `link-worktree-untracked.sh` で作成した symlink だけを機械的に除外する。

根拠: `scripts/worktree-status.sh:1-58`

## 動作の概要

現在の repository root が `.claude/worktrees/` 配下でなければ、`git status --porcelain` をそのまま出力する。worktree 内では Claude/Codex の `session-paths.sh` から session tmp directory を解決し、`worktree-untracked-symlinks.txt` があれば NUL 区切り porcelain status を読む。`??` または `!!` の path が manifest と完全一致するか、manifest entry の親 directory なら除外し、残りを出力する。

根拠: `scripts/worktree-status.sh:8-58`

## 重要な設計判断

- manifest がない、session path helper がない、または通常 worktree の場合は unfiltered status を返す。単体 `/work` と未更新のインストール環境を変えないため。
- tracked change は manifest path と重なっても除外しない。self-created symlink として発生する `??`/`!!` だけを対象にし、実際の編集を隠さないため。

## 統合ポイント

- 呼び出し元: `commands/work.md` G-2、`commands/task.md` Phase 2
- 入力: `hooks/lib/session-paths.sh` と `scripts/link-worktree-untracked.sh` が作る manifest
- テスト: `tests/scripts/test-worktree-status.sh`

## 注意事項・既知の制限

manifest は linker が新規に作成した symlink のみを記録する。manifest にない path は意図的に除外しない。
