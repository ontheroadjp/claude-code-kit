# `tests/scripts/test-link-worktree-untracked.sh`

## 目的・役割

`scripts/link-worktree-untracked.sh` の lazy linking と venv 実体構築を functional に検証する shell test。`prepare` が symlink を作らないこと、指定した untracked/ignored path だけを link すること、manifest の冪等性と安全な拒否、`venv` サブコマンドの安全策と `uv`/`python3 -m venv` の両方の構築経路を確認する。

根拠: `tests/scripts/test-link-worktree-untracked.sh:1-35`

## 動作概要

`mktemp -d` 配下に source と destination repository を作る。source には tracked file、top-level untracked file/directory、tracked directory 配下の ignored `site/node_modules`、`.claude` fixture を用意する。Codex session-paths stub を用意して `prepare <SRC_DIR>` を実行し、source file と空 manifest が作られる一方で symlink が1つも作られないことを確認する。続けて `link untracked.txt` と `link site/node_modules` を実行し、指定 path だけが正しい source target を持つ symlink になることを確認する。

根拠: `tests/scripts/test-link-worktree-untracked.sh:36-89`

同じ path の再 link は manifest を重複させない。tracked path、parent traversal、`.claude` path、source に存在しない path の `link` は失敗することを確認する。

根拠: `tests/scripts/test-link-worktree-untracked.sh:91-119`

`venv` サブコマンドは以下を検証する（issue #374）:
- basename が `venv`・`.venv` 以外、parent traversal、既存 path はいずれも拒否される（`uv`・`.gitignore` 設定に依存しないため常時実行）
- 対象 path が destination の `.gitignore` に含まれていない場合は拒否される（build tool 非依存）
- `.gitignore` に `.venv/` を追記した後、`uv` が使える環境では `uv venv` により symlink ではない実体ディレクトリが作られ、manifest に記録されることを確認する（`uv` が無い環境では SKIP）
- `PATH` から `uv` のインストールディレクトリを実体パス解決（`pwd -P`）した上で除外した環境で実行し、`python3 -m venv` フォールバックが `pyvenv.cfg` を持つ実体ディレクトリを作ることを確認する（`python3` が無い環境では SKIP）。`command -v uv` が返す path が `PATH` のエントリと文字列として一致しない場合（例: `share/..` を含む未正規化 path と正規化された path が両方 `PATH` にある）があるため、単純な文字列比較ではなく実体パスで比較する。

根拠: `tests/scripts/test-link-worktree-untracked.sh:120-201`, issue #374

## 重要な設計判断

`tests/hooks/test-approval-hooks.sh` と同じ「`mktemp -d` + `trap` によるクリーンアップ」パターンを踏襲し、実リポジトリの状態に影響しない隔離された一時ディレクトリで検証する。static assertion ではなく実際にスクリプトを実行して symlink の生成結果を検証する functional test とした（`tests/commands/test-work-multi.sh` 側は文言の静的検証のみを担当し、役割を分離している）。

fixture の `.gitignore` に `.claude/` を明示し、global gitignore の影響を受けず `.claude` の拒否を検証する。

全ての呼び出しで `HOME` をテスト専用 directory へ上書きし、開発機の installed hook に依存しない決定論的な検証にする。

venv 関連の assertion は、実行環境に `uv`・`python3` が無くても全体が失敗しないよう `command -v` で存在確認したうえで SKIP する。`uv`/`python3` はこのテストスイート実行環境に必須ツールとして強制しない（CI 必須ではなく README に案内された手動実行のテストであるため）。

`uv` の PATH 除外は、ディレクトリ文字列の単純一致ではなく `cd "$dir" && pwd -P` で実体パスに正規化してから比較する。開発機の PATH に同一ディレクトリを指す複数の表記（正規化済み path と `share/..` を含む未正規化 path）が同時に存在するケースが実際にあり、文字列一致だけでは除外漏れが起きて `uv` が意図せず使われ続けることを確認した。

## 統合ポイント

- 対象: `scripts/link-worktree-untracked.sh`
- 実行: `bash tests/scripts/test-link-worktree-untracked.sh`
- 外部ツール（venv assertion のみ、任意）: `uv`、`python3`

## 注意事項・既知の制限

- `node_modules` のような「セッション中に書き換わる」性質そのものはこのテストでは検証していない（symlink が正しい場所に作られることのみを検証する）。並行書き込みによる衝突リスクは `commands/work-multi.md`・`CLAUDE.md` の既知の限界として文書化するに留めている。
- manifest テストで使う `hooks/lib/session-paths.sh` スタブは `session-tmp-dir` モードのみを模擬する最小実装（固定ディレクトリを1行 echo するだけ）であり、`hooks/lib/session-paths.sh` 本体の `session-approved` モードや `session_id_resolve` のロジック自体は検証しない（それらは別のテスト・実機検証で担保する）。
- `venv` の実ビルド検証（`uv` 経路・`python3 -m venv` フォールバック経路）は、テスト実行環境に該当ツールが無い場合 SKIP されるため、CI や開発機の構成によっては拒否系の assertion のみが実行される。

## 変更履歴（git log より自動生成）

- fa82b85 feat(#374): build venv/.venv via uv in /work-multi worktrees instead of lazy-linking
- e624ef2 #328 Add lazy worktree linker (#329)
- 1aa3c2d fix(#318): distinguish worktree-untracked symlinks from real changes via manifest
- 69c1e80 fix(#296): use worktree- prefix only for branch classification and NUL-delimited untracked enumeration
- bc4ae7b feat(#296): add /work-multi worktree-isolated entry point
