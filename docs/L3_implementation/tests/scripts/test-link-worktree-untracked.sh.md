# `tests/scripts/test-link-worktree-untracked.sh`

## 目的・役割

`scripts/link-worktree-untracked.sh` の symlink 挙動を functional に検証する shell test（issue #296、PR #304、issue #318）。トップレベル untracked ファイル、tracked ディレクトリ配下にネストした untracked ディレクトリ、`.git`/`.claude` の除外（ネストしたパスの漏れ含む）、冪等性、および manifest 書き出し（issue #318）を実際に一時 git リポジトリを作って確認する。

根拠: `tests/scripts/test-link-worktree-untracked.sh:1-35`

## 動作概要

`mktemp -d` で作った一時ディレクトリ配下に source（`SRC_DIR`）と destination（`DST_DIR`）の2つの git リポジトリを作る。source には実リポジトリと同じ `.gitignore`（`.claude/` を除外）、tracked ファイル、tracked ディレクトリ配下にネストした untracked ディレクトリ（`site/node_modules`）、トップレベル untracked ファイル/ディレクトリ、`.claude/settings.local.json`、`.claude/worktrees/dummy` を用意する。destination で `HOME` を `hooks/lib/session-paths.sh` が存在しない一時ディレクトリ（`NO_HOOKS_HOME`）に向けた状態で `scripts/link-worktree-untracked.sh <SRC_DIR>` を実行し、symlink の生成先とリンク先が期待通りか（`readlink` と比較）、`.claude` および `.claude/settings.local.json`（ネストしたパスの個別リーク）が存在しないこと、manifest 未インストール環境でもエラーなく完了することを確認する。同じ `HOME` のまま再実行し、エラーなく完了する（冪等性）ことも確認する。

根拠: `tests/scripts/test-link-worktree-untracked.sh:36-89`

続けて、`HOME` を `.claude/hooks/lib/session-paths.sh` のスタブ（`session-tmp-dir` として固定の一時ディレクトリを返す）を配置した別の一時ディレクトリ（`WITH_HOOKS_HOME`）に向け、新しい destination（`DST_DIR2`）に対してスクリプトを実行する。スタブが返した session tmp directory 配下の `worktree-untracked-symlinks.txt` が実際に作成され、symlink 化した全ての相対パス（`untracked.txt`・`untracked_dir`・`site/node_modules`）を含むことを確認する（issue #318）。

根拠: `tests/scripts/test-link-worktree-untracked.sh:91-119`

## 重要な設計判断

`tests/hooks/test-approval-hooks.sh` と同じ「`mktemp -d` + `trap` によるクリーンアップ」パターンを踏襲し、実リポジトリの状態に影響しない隔離された一時ディレクトリで検証する。static assertion ではなく実際にスクリプトを実行して symlink の生成結果を検証する functional test とした（`tests/commands/test-work-multi.sh` 側は文言の静的検証のみを担当し、役割を分離している）。

フィクスチャに実リポジトリと同じ `.gitignore`（`.claude/` エントリ）を明示的に用意している。当初これを省いていたところ、開発機のグローバル `.gitignore`（`.claude/settings.local.json` のようなファイル単位のルール）が意図せず適用され、`.claude/` がディレクトリ単位ではなく個別ファイル単位で ignored 報告される環境依存の不具合が判明した（PR #304 レビュー対応）。ローカル `.gitignore` を明示することでこの環境依存性を排除し、`.claude/*` ネストパスの除外も明示的にテストする。

全てのスクリプト呼び出しで `HOME` をテスト専用の一時ディレクトリ（`NO_HOOKS_HOME` または `WITH_HOOKS_HOME`）へ明示的に上書きしている（issue #318）。開発機の実際の `$HOME` に `~/.claude/hooks/lib/session-paths.sh` がインストール済みの場合、上書きしないとテストの挙動が開発機の状態に依存してしまう（manifest が書かれるかどうか、書かれる場合の書き込み先が実セッションの tmp directory になるかどうかが変わる）ため、決定論的な検証には常に `HOME` の明示的な制御が必要。

## 統合ポイント

- 対象: `scripts/link-worktree-untracked.sh`
- 実行: `bash tests/scripts/test-link-worktree-untracked.sh`

## 注意事項・既知の制限

- `node_modules` のような「セッション中に書き換わる」性質そのものはこのテストでは検証していない（symlink が正しい場所に作られることのみを検証する）。並行書き込みによる衝突リスクは `commands/work-multi.md`・`CLAUDE.md` の既知の限界として文書化するに留めている。
- manifest テストで使う `hooks/lib/session-paths.sh` スタブは `session-tmp-dir` モードのみを模擬する最小実装（固定ディレクトリを1行 echo するだけ）であり、`hooks/lib/session-paths.sh` 本体の `session-approved` モードや `session_id_resolve` のロジック自体は検証しない（それらは別のテスト・実機検証で担保する）。

## 変更履歴（git log より自動生成）

- 1aa3c2d fix(#318): distinguish worktree-untracked symlinks from real changes via manifest
- 69c1e80 fix(#296): use worktree- prefix only for branch classification and NUL-delimited untracked enumeration
- bc4ae7b feat(#296): add /work-multi worktree-isolated entry point
