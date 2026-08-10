# `tests/scripts/test-link-worktree-untracked.sh`

## 目的・役割

`scripts/link-worktree-untracked.sh` の symlink 挙動を functional に検証する shell test（issue #296、PR #304）。トップレベル untracked ファイル、tracked ディレクトリ配下にネストした untracked ディレクトリ、`.git`/`.claude` の除外（ネストしたパスの漏れ含む）、冪等性を実際に一時 git リポジトリを作って確認する。

根拠: `tests/scripts/test-link-worktree-untracked.sh:1-35`

## 動作概要

`mktemp -d` で作った一時ディレクトリ配下に source（`SRC_DIR`）と destination（`DST_DIR`）の2つの git リポジトリを作る。source には実リポジトリと同じ `.gitignore`（`.claude/` を除外）、tracked ファイル、tracked ディレクトリ配下にネストした untracked ディレクトリ（`site/node_modules`）、トップレベル untracked ファイル/ディレクトリ、`.claude/settings.local.json`、`.claude/worktrees/dummy` を用意する。destination で `scripts/link-worktree-untracked.sh <SRC_DIR>` を実行し、symlink の生成先とリンク先が期待通りか（`readlink` と比較）、`.claude` および `.claude/settings.local.json`（ネストしたパスの個別リーク）が存在しないことを確認する。最後に同じスクリプトを再実行し、エラーなく完了する（冪等性）ことを確認する。

根拠: `tests/scripts/test-link-worktree-untracked.sh:36-86`

## 重要な設計判断

`tests/hooks/test-approval-hooks.sh` と同じ「`mktemp -d` + `trap` によるクリーンアップ」パターンを踏襲し、実リポジトリの状態に影響しない隔離された一時ディレクトリで検証する。static assertion ではなく実際にスクリプトを実行して symlink の生成結果を検証する functional test とした（`tests/commands/test-work-multi.sh` 側は文言の静的検証のみを担当し、役割を分離している）。

フィクスチャに実リポジトリと同じ `.gitignore`（`.claude/` エントリ）を明示的に用意している。当初これを省いていたところ、開発機のグローバル `.gitignore`（`.claude/settings.local.json` のようなファイル単位のルール）が意図せず適用され、`.claude/` がディレクトリ単位ではなく個別ファイル単位で ignored 報告される環境依存の不具合が判明した（PR #304 レビュー対応）。ローカル `.gitignore` を明示することでこの環境依存性を排除し、`.claude/*` ネストパスの除外も明示的にテストする。

## 統合ポイント

- 対象: `scripts/link-worktree-untracked.sh`
- 実行: `bash tests/scripts/test-link-worktree-untracked.sh`

## 注意事項・既知の制限

`node_modules` のような「セッション中に書き換わる」性質そのものはこのテストでは検証していない（symlink が正しい場所に作られることのみを検証する）。並行書き込みによる衝突リスクは `commands/work-multi.md`・`CLAUDE.md` の既知の限界として文書化するに留めている。

## 変更履歴（git log より自動生成）

- bc4ae7b feat(#296): add /work-multi worktree-isolated entry point
