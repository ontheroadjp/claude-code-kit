# `scripts/link-worktree-untracked.sh`

## 目的・役割

`EnterWorktree` が作成した新規 worktree に、元の working tree の untracked/ignored ファイル・ディレクトリを symlink する。`commands/work-multi.md` の Step 0.3 から呼ばれる（issue #296）。

根拠: `scripts/link-worktree-untracked.sh:1-3`

## 動作概要

引数1つ（元の working tree の絶対パス）を取り、`git -C <元パス> status --porcelain -z --ignored=matching` の NUL 区切り出力から `??`（untracked）・`!!`（ignored）の2ステータスのエントリを抽出し、untracked/ignored パス一覧を取得する。`.git`・`.claude` およびその配下（`.git/*`・`.claude/*`）はスキップする。各パスについて、既に symlink が存在すればスキップ（冪等性）、symlink ではない実体が既に存在すれば警告して skip、それ以外は `mkdir -p` で親ディレクトリを作成した上で、カレントディレクトリ（新しい worktree）内の同一相対パスへ symlink を作成する。

根拠: `scripts/link-worktree-untracked.sh:11-40`

## 重要な設計判断

- 当初は `git clean -ndx` の人間向け出力（`Would remove <path>`）を行単位でパースしていたが、PR #304 の Codex CLI レビューで、この出力形式が特殊文字（空白・改行等）を含むパスをクォート・エスケープして表示するため実パスと一致しない不具合を指摘された。`git status --porcelain -z --ignored=matching` は NUL 区切りでパスをエスケープなしに出力するため、この問題を構造的に回避できる。
- 除外対象は `.git`・`.claude` とその配下のみ。`.git` は worktree 自身の git-dir 連携のため触れてはならない。`.claude` は `EnterWorktree` 自身が worktree を `.claude/worktrees/<name>` 配下に格納する予約ディレクトリのため、丸ごと symlink すると新しい worktree の中に worktrees ディレクトリ自身への自己参照ループが生じる。当初は `.claude` の完全一致のみを除外していたが、テスト実行環境のグローバル `.gitignore`（例: `**/.claude/settings.local.json` のようなファイル単位の除外ルール）が存在すると、ディレクトリ全体ではなく `.claude/settings.local.json` のような個別ファイル単位で ignored 報告されるケースがあることが判明し、`.claude` 配下のネストしたパスも `.claude/*` パターンで除外するよう修正した（PR #304 レビュー対応）。
- `node_modules` 等の依存ディレクトリを個別に除外する案は採用しなかった。この toolkit は特定リポジトリ専用ではなく任意のリポジトリで使われるため、リポジトリ・エコシステムごとに異なる依存ディレクトリ名をハードコードすると汎用性の前提と矛盾する。既知の限界（共有可変状態の衝突リスク）として `commands/work-multi.md`・`CLAUDE.md` に文書化するに留めた。
- coding-sh.md 準拠（`set -euo pipefail`、変数展開のダブルクオート、ShellCheck 通過）。

根拠: `scripts/link-worktree-untracked.sh:13-28`, issue #296, PR #304

## 統合ポイント

- 呼び出し元: `commands/work-multi.md` Step 0.3
- CI: `.github/workflows/shellcheck.yml` が `*.sh` として lint する

## 注意事項・既知の制限

- `node_modules` 等セッション中に書き換わる untracked ディレクトリも symlink 対象に含まれるため、同じ依存ディレクトリを持つ複数 worktree セッションでパッケージマネージャの書き込み操作を同時実行すると衝突し得る（`commands/work-multi.md` 参照）。
- symlink ではない実体パスが既に存在する場合は上書きせず警告のみを標準エラーに出力し処理を継続する（`set -e` によるスクリプト全体の停止はしない）。

## 変更履歴（git log より自動生成）

- bc4ae7b feat(#296): add /work-multi worktree-isolated entry point
