# `scripts/link-worktree-untracked.sh`

## 目的・役割

`EnterWorktree` が作成した新規 worktree に、元の working tree の untracked/ignored ファイル・ディレクトリを symlink する。`commands/work-multi.md` の Step 0.3 から呼ばれる（issue #296）。

根拠: `scripts/link-worktree-untracked.sh:1-3`

## 動作概要

引数1つ（元の working tree の絶対パス）を取り、`git -C <元パス> clean -ndx` の dry-run 出力（`Would remove <相対パス>`）から untracked/ignored のルートパス一覧を取得する。`.git`・`.claude` はスキップする。各パスについて、既に symlink が存在すればスキップ（冪等性）、symlink ではない実体が既に存在すれば警告して skip、それ以外は `mkdir -p` で親ディレクトリを作成した上で、カレントディレクトリ（新しい worktree）内の同一相対パスへ symlink を作成する。

根拠: `scripts/link-worktree-untracked.sh:11-33`

## 重要な設計判断

- `git clean -ndx` はディレクトリ単位で untracked ルートを1行にまとめて報告する（配下を再帰列挙しない）ため、ファイル単位ではなくディレクトリ単位で symlink でき、シンボリックリンク数を最小化できる。
- 除外対象は `.git` と `.claude` の2つのみ。`.git` は worktree 自身の git-dir 連携のため触れてはならない。`.claude` は `EnterWorktree` 自身が worktree を `.claude/worktrees/<name>` 配下に格納する予約ディレクトリのため、丸ごと symlink すると新しい worktree の中に worktrees ディレクトリ自身への自己参照ループが生じる。
- `node_modules` 等の依存ディレクトリを個別に除外する案は採用しなかった。この toolkit は特定リポジトリ専用ではなく任意のリポジトリで使われるため、リポジトリ・エコシステムごとに異なる依存ディレクトリ名をハードコードすると汎用性の前提と矛盾する。既知の限界（共有可変状態の衝突リスク）として `commands/work-multi.md`・`CLAUDE.md` に文書化するに留めた。
- coding-sh.md 準拠（`set -euo pipefail`、変数展開のダブルクオート、ShellCheck 通過）。

根拠: `scripts/link-worktree-untracked.sh:13-21`, issue #296

## 統合ポイント

- 呼び出し元: `commands/work-multi.md` Step 0.3
- CI: `.github/workflows/shellcheck.yml` が `*.sh` として lint する

## 注意事項・既知の制限

- `node_modules` 等セッション中に書き換わる untracked ディレクトリも symlink 対象に含まれるため、同じ依存ディレクトリを持つ複数 worktree セッションでパッケージマネージャの書き込み操作を同時実行すると衝突し得る（`commands/work-multi.md` 参照）。
- symlink ではない実体パスが既に存在する場合は上書きせず警告のみを標準エラーに出力し処理を継続する（`set -e` によるスクリプト全体の停止はしない）。
