# `tests/scripts/test-link-worktree-untracked.sh`

## 目的・役割

`scripts/link-worktree-untracked.sh` の lazy linking を functional に検証する shell test。`prepare` が symlink を作らないこと、指定した untracked/ignored path だけを link すること、manifest の冪等性と安全な拒否を確認する。

根拠: `tests/scripts/test-link-worktree-untracked.sh:1-35`

## 動作概要

`mktemp -d` 配下に source と destination repository を作る。source には tracked file、top-level untracked file/directory、tracked directory 配下の ignored `site/node_modules`、`.claude` fixture を用意する。Codex session-paths stub を用意して `prepare <SRC_DIR>` を実行し、source file と空 manifest が作られる一方で symlink が1つも作られないことを確認する。続けて `link untracked.txt` と `link site/node_modules` を実行し、指定 path だけが正しい source target を持つ symlink になることを確認する。

根拠: `tests/scripts/test-link-worktree-untracked.sh:36-89`

同じ path の再 link は manifest を重複させない。tracked path、parent traversal、`.claude` path、source に存在しない path の `link` は失敗することを確認する。

根拠: `tests/scripts/test-link-worktree-untracked.sh:91-119`

## 重要な設計判断

`tests/hooks/test-approval-hooks.sh` と同じ「`mktemp -d` + `trap` によるクリーンアップ」パターンを踏襲し、実リポジトリの状態に影響しない隔離された一時ディレクトリで検証する。static assertion ではなく実際にスクリプトを実行して symlink の生成結果を検証する functional test とした（`tests/commands/test-work-multi.sh` 側は文言の静的検証のみを担当し、役割を分離している）。

fixture の `.gitignore` に `.claude/` を明示し、global gitignore の影響を受けず `.claude` の拒否を検証する。

全ての呼び出しで `HOME` をテスト専用 directory へ上書きし、開発機の installed hook に依存しない決定論的な検証にする。

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
