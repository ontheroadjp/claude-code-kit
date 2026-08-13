# `scripts/link-worktree-untracked.sh`

## 目的・役割

`EnterWorktree` が作成した worktree に、元の working tree の必要な untracked/ignored path だけを lazy symlink する。`commands/work-multi.md` の Step 0.3 から呼ばれる。

根拠: `scripts/link-worktree-untracked.sh:1-3`

## 動作概要

`prepare <source-working-tree>` は `hooks/lib/session-paths.sh` で解決した current session tmp directory に、source worktree の絶対 path と空の manifest を記録する。この操作は symlink を作らない。`link <relative-path>` は source 記録を読み、指定 path が空・絶対 path・parent traversal・`.git`・`.claude` でないことを確認する。続いて source 側の `git status --porcelain -z --ignored=matching -- <path>` が `??` または `!!` を報告する場合だけ、current worktree の同じ相対 path に symlink を作る。既存 symlink は同じ source target の場合だけ許容し、実体や異なる target は拒否する。

`link` は成功した path を `worktree-untracked-symlinks.txt` へ追記する。同じ path がすでに記録済みなら追記しないため、再実行は冪等である。lazy link は current session の source と manifest が必要なので、session path helper がない、または `prepare` が未実行なら明示的に失敗する。

根拠: `scripts/link-worktree-untracked.sh:11-59`

## 重要な設計判断

- 当初は `git clean -ndx` の人間向け出力（`Would remove <path>`）を行単位でパースしていたが、PR #304 の Codex CLI レビューで、この出力形式が特殊文字（空白・改行等）を含むパスをクォート・エスケープして表示するため実パスと一致しない不具合を指摘された。`git status --porcelain -z --ignored=matching` は NUL 区切りでパスをエスケープなしに出力するため、この問題を構造的に回避できる。
- 除外対象は `.git`・`.claude` とその配下のみ。`.git` は worktree 自身の git-dir 連携のため触れてはならない。`.claude` は `EnterWorktree` 自身が worktree を `.claude/worktrees/<name>` 配下に格納する予約ディレクトリのため、丸ごと symlink すると新しい worktree の中に worktrees ディレクトリ自身への自己参照ループが生じる。当初は `.claude` の完全一致のみを除外していたが、テスト実行環境のグローバル `.gitignore`（例: `**/.claude/settings.local.json` のようなファイル単位の除外ルール）が存在すると、ディレクトリ全体ではなく `.claude/settings.local.json` のような個別ファイル単位で ignored 報告されるケースがあることが判明し、`.claude` 配下のネストしたパスも `.claude/*` パターンで除外するよう修正した（PR #304 レビュー対応）。
- linker は path 名（`node_modules` 等）を特別扱いしない。任意の consumer repository に対応し、必要になった ignored directory だけを同じ検証で link するため。
- coding-sh.md 準拠（`set -euo pipefail`、変数展開のダブルクオート、ShellCheck 通過）。
- symlink 化した path は `.gitignore` の directory-only pattern に一致せず `git status` に `??`/`!!` として現れることがある。git 設定を変更せず manifest と `worktree-status.sh` で自己作成 link だけを除外する。

根拠: `scripts/link-worktree-untracked.sh:13-28`, `scripts/link-worktree-untracked.sh:13-24,58`, issue #296, PR #304, issue #318

## 統合ポイント

- 呼び出し元: `commands/work-multi.md` Step 0.3
- 呼び出すもの: `hooks/lib/session-paths.sh`、`git status`、`ln`
- manifest の利用元: `commands/work.md` G-2、`commands/task.md` Phase 2
- CI: `.github/workflows/shellcheck.yml` が `*.sh` として lint する

## 注意事項・既知の制限

- lazy link した `node_modules` 等へ複数 worktree session が同時に書き込むと衝突し得る。
- `link` は安全に上書きできない既存 path や source 上の tracked/unavailable path を失敗として扱う。次の path を推測して続行しない。

## 変更履歴（git log より自動生成）

- 1aa3c2d fix(#318): distinguish worktree-untracked symlinks from real changes via manifest
- 69c1e80 fix(#296): use worktree- prefix only for branch classification and NUL-delimited untracked enumeration
- bc4ae7b feat(#296): add /work-multi worktree-isolated entry point
