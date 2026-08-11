# `scripts/link-worktree-untracked.sh`

## 目的・役割

`EnterWorktree` が作成した新規 worktree に、元の working tree の untracked/ignored ファイル・ディレクトリを symlink する。`commands/work-multi.md` の Step 0.3 から呼ばれる（issue #296）。

根拠: `scripts/link-worktree-untracked.sh:1-3`

## 動作概要

引数1つ（元の working tree の絶対パス）を取り、`git -C <元パス> status --porcelain -z --ignored=matching` の NUL 区切り出力から `??`（untracked）・`!!`（ignored）の2ステータスのエントリを抽出し、untracked/ignored パス一覧を取得する。`.git`・`.claude` およびその配下（`.git/*`・`.claude/*`）はスキップする。各パスについて、既に symlink が存在すればスキップ（冪等性）、symlink ではない実体が既に存在すれば警告して skip、それ以外は `mkdir -p` で親ディレクトリを作成した上で、カレントディレクトリ（新しい worktree）内の同一相対パスへ symlink を作成する。

symlink ループ開始前に、`${HOME}/.claude/hooks/lib/session-paths.sh`（存在しなければ `${HOME}/.codex/hooks/lib/session-paths.sh`）を `session-tmp-dir` モードで呼び、自セッションの tmp directory を解決する。解決できた場合、その配下の `worktree-untracked-symlinks.txt` を空で作成し、以後 symlink を1つ作成するたびにその相対パスを1行追記する（既に symlink として存在しスキップされたパスは対象外）。解決できない場合（`hooks/lib/session-paths.sh` 未インストール）は manifest を一切書かず、この機能追加前と同じ挙動になる。

根拠: `scripts/link-worktree-untracked.sh:11-59`

## 重要な設計判断

- 当初は `git clean -ndx` の人間向け出力（`Would remove <path>`）を行単位でパースしていたが、PR #304 の Codex CLI レビューで、この出力形式が特殊文字（空白・改行等）を含むパスをクォート・エスケープして表示するため実パスと一致しない不具合を指摘された。`git status --porcelain -z --ignored=matching` は NUL 区切りでパスをエスケープなしに出力するため、この問題を構造的に回避できる。
- 除外対象は `.git`・`.claude` とその配下のみ。`.git` は worktree 自身の git-dir 連携のため触れてはならない。`.claude` は `EnterWorktree` 自身が worktree を `.claude/worktrees/<name>` 配下に格納する予約ディレクトリのため、丸ごと symlink すると新しい worktree の中に worktrees ディレクトリ自身への自己参照ループが生じる。当初は `.claude` の完全一致のみを除外していたが、テスト実行環境のグローバル `.gitignore`（例: `**/.claude/settings.local.json` のようなファイル単位の除外ルール）が存在すると、ディレクトリ全体ではなく `.claude/settings.local.json` のような個別ファイル単位で ignored 報告されるケースがあることが判明し、`.claude` 配下のネストしたパスも `.claude/*` パターンで除外するよう修正した（PR #304 レビュー対応）。
- `node_modules` 等の依存ディレクトリを個別に除外する案は採用しなかった。この toolkit は特定リポジトリ専用ではなく任意のリポジトリで使われるため、リポジトリ・エコシステムごとに異なる依存ディレクトリ名をハードコードすると汎用性の前提と矛盾する。既知の限界（共有可変状態の衝突リスク）として `commands/work-multi.md`・`CLAUDE.md` に文書化するに留めた。
- coding-sh.md 準拠（`set -euo pipefail`、変数展開のダブルクオート、ShellCheck 通過）。
- symlink 化した untracked/ignored パスは `.gitignore` のディレクトリ限定パターン（末尾 `/`）に一致しないため（git は symlink をディレクトリとして扱わない）、`git status` に `??`/`!!` として現れる。実機検証で `git check-ignore -v site/node_modules` が非ignoredと判定することを確認した。git 側の ignore 判定を変える案（`git config --worktree core.excludesFile` + `extensions.worktreeConfig`）も実機検証し機能することを確認したが不採用とした: 目的は「git status を完全にクリーンにする」ことではなく「予期しない untracked ファイルを見た際に、自分が作った symlink だと即座に判別できる」ことであり、git 設定を変更しない manifest 方式の方がスコープが小さく、`ExitWorktree`（harness機能で変更不可）が未コミットとして数える挙動自体は残るが、manifest と突き合わせれば無駄な調査を避けられる（issue #318）。
- manifest への追記は symlink 作成ループの内側で行う（ループはパイプ経由のサブシェルで実行されるため、ループ内で変数を蓄積してループ外で使うことはできない。ファイルへの直接追記はサブシェル境界に影響されないためこの制約を回避できる）。

根拠: `scripts/link-worktree-untracked.sh:13-28`, `scripts/link-worktree-untracked.sh:13-24,58`, issue #296, PR #304, issue #318

## 統合ポイント

- 呼び出し元: `commands/work-multi.md` Step 0.3
- 呼び出すもの: `hooks/lib/session-paths.sh`（`bash` で直接実行、`source` はしない。`session-tmp-dir` モード）
- manifest の利用元: `commands/work.md` G-2、`commands/task.md` Phase 2
- CI: `.github/workflows/shellcheck.yml` が `*.sh` として lint する

## 注意事項・既知の制限

- `node_modules` 等セッション中に書き換わる untracked ディレクトリも symlink 対象に含まれるため、同じ依存ディレクトリを持つ複数 worktree セッションでパッケージマネージャの書き込み操作を同時実行すると衝突し得る（`commands/work-multi.md` 参照）。
- symlink ではない実体パスが既に存在する場合は上書きせず警告のみを標準エラーに出力し処理を継続する（`set -e` によるスクリプト全体の停止はしない）。
- manifest への追記は「このスクリプト呼び出しで新規に symlink したパス」のみが対象。既に symlink として存在しスキップされたパス（例: 同一 worktree でスクリプトを2回目以降に実行した場合）は追記されない。`/work-multi` は Step 0.3 で1回だけ呼ぶ設計のため通常は問題にならない。
- `.pytest_cache` のように元 working tree 側にネストした `.gitignore` を持つディレクトリは、`git status --porcelain -z --ignored=matching` がディレクトリ単位ではなく配下のファイル単位で `??`/`!!` を報告するため、symlink・manifest エントリともに個別ファイル単位になる（例: `.pytest_cache/.gitignore`・`.pytest_cache/v` 等）。一方 `site/node_modules` のようにネストした `.gitignore` を持たないディレクトリは1エントリに集約される。`commands/work.md` G-2・`commands/task.md` Phase 2 の manifest 突き合わせは、この違いを前提に「完全一致または親ディレクトリ一致」で判定する。

## 変更履歴（git log より自動生成）

- bc4ae7b feat(#296): add /work-multi worktree-isolated entry point
