# `scripts/link-worktree-untracked.sh`

## 目的・役割

`EnterWorktree` が作成した worktree に、元の working tree の必要な untracked/ignored path だけを lazy symlink する。`commands/work-multi.md` の Step 0.3 から呼ばれる。venv/.venv だけは symlink ではなく、`uv`（フォールバック時は `python3 -m venv`）で worktree 内に独立した実体の仮想環境を構築する `venv` サブコマンドも提供する（issue #374）。

根拠: `scripts/link-worktree-untracked.sh:1-3`

## 動作概要

`prepare <source-working-tree>` は `hooks/lib/session-paths.sh` で解決した current session tmp directory に、source worktree の絶対 path と空の manifest を記録する。この操作は symlink を作らない。`link <relative-path>` は source 記録を読み、指定 path が空・絶対 path・parent traversal・`.git`・`.claude` でないことを確認する。続いて source 側の `git status --porcelain -z --ignored=matching -- <path>` が `??` または `!!` を報告する場合だけ、current worktree の同じ相対 path に symlink を作る。既存 symlink は同じ source target の場合だけ許容し、実体や異なる target は拒否する。

`link` は成功した path を `worktree-untracked-symlinks.txt` へ追記する。同じ path がすでに記録済みなら追記しないため、再実行は冪等である。lazy link は current session の source と manifest が必要なので、session path helper がない、または `prepare` が未実行なら明示的に失敗する。

根拠: `scripts/link-worktree-untracked.sh:11-59`

`venv <relative-path>` は `link` とは独立した経路で、source worktree を一切参照しない。まず basename が `venv`・`.venv` のいずれでもない場合、path が既に存在する（symlink・実体を問わない）場合に拒否する。続いて `git check-ignore -q -- "${relative_path}/"`（末尾スラッシュを付けて問い合わせる）で対象 path が現在の worktree の `.gitignore` で ignore されていることを確認し、ignore されていなければ拒否する。ここまでを通過した場合のみ、`uv` があれば `uv venv "$relative_path"`、なければ `python3 -m venv "$relative_path"` で実体のディレクトリを構築する。成功した path は `link` と同じ manifest（`append_manifest_path`）に記録するため、`worktree-status.sh` は symlink かどうかを区別せず、自己作成 path として同じ仕組みで除外する。

根拠: `scripts/link-worktree-untracked.sh:124-158`, issue #374

## 重要な設計判断

- 当初は `git clean -ndx` の人間向け出力（`Would remove <path>`）を行単位でパースしていたが、PR #304 の Codex CLI レビューで、この出力形式が特殊文字（空白・改行等）を含むパスをクォート・エスケープして表示するため実パスと一致しない不具合を指摘された。`git status --porcelain -z --ignored=matching` は NUL 区切りでパスをエスケープなしに出力するため、この問題を構造的に回避できる。
- 除外対象は `.git`・`.claude` とその配下のみ。`.git` は worktree 自身の git-dir 連携のため触れてはならない。`.claude` は `EnterWorktree` 自身が worktree を `.claude/worktrees/<name>` 配下に格納する予約ディレクトリのため、丸ごと symlink すると新しい worktree の中に worktrees ディレクトリ自身への自己参照ループが生じる。当初は `.claude` の完全一致のみを除外していたが、テスト実行環境のグローバル `.gitignore`（例: `**/.claude/settings.local.json` のようなファイル単位の除外ルール）が存在すると、ディレクトリ全体ではなく `.claude/settings.local.json` のような個別ファイル単位で ignored 報告されるケースがあることが判明し、`.claude` 配下のネストしたパスも `.claude/*` パターンで除外するよう修正した（PR #304 レビュー対応）。
- linker は path 名（`node_modules` 等）を特別扱いしない。任意の consumer repository に対応し、必要になった ignored directory だけを同じ検証で link するため。ただし venv/.venv だけは `venv` サブコマンドで例外的に特別扱いする。venv はセッション中に `pip install` 等で書き込まれるため、`node_modules` と同様に symlink 経由の共有が書き込み衝突を招くが、`node_modules` と異なり「書き込みが必要な path は link 前に worktree 内へ独立して作成する」という一般則をそのまま使うと、対象 repository ごとに異なる依存関係の再インストールを都度指示する必要がある。venv は `uv venv`/`python3 -m venv` という決まった構築コマンドがあるため、path 名を特別扱いする合理性がある。
- `venv` は source worktree の状態を一切見ない（`is_linkable_source_path` を使わない）。symlink ではなく新規に実体を構築するため、source 側が untracked/ignored かどうかは無関係。
- `venv` の構築前に対象 path が `.gitignore` で ignore されていることを必須にした。これにより構築した venv は常に `git status` 上 `!!`（ignored）として扱われ、`git add -A` 等でも誤って拾われないことを構造的に保証する。問い合わせは `git check-ignore -q -- "${relative_path}/"` のように末尾スラッシュを付ける。ディレクトリがまだ存在しない状態で末尾スラッシュなしに問い合わせると、`.gitignore` の directory-only pattern（例: `.venv/`）が誤って「非 ignore」と判定される git の挙動があるため（末尾スラッシュを付けたクエリなら、plain pattern・directory-only pattern のどちらでもディレクトリ作成前に正しく判定できることを実機で確認済み）。
- 構築コマンドは `uv` を優先し、なければ `python3 -m venv`（pip 同梱）にフォールバックする。当初は `uv` が無ければ拒否する設計だったが、`uv` は必須ツールではなく consumer repository に必ず入っている前提を置けないため、標準ライブラリで完結するフォールバックを持たせた（issue #374 のユーザーフィードバック）。
- coding-sh.md 準拠（`set -euo pipefail`、変数展開のダブルクオート、ShellCheck 通過）。
- symlink 化した path は `.gitignore` の directory-only pattern に一致せず `git status` に `??`/`!!` として現れることがある。git 設定を変更せず manifest と `worktree-status.sh` で自己作成 link だけを除外する。venv の実体ディレクトリも同じ manifest で除外されるため、`worktree-status.sh` 側の変更は不要だった。

根拠: `scripts/link-worktree-untracked.sh:13-28`, `scripts/link-worktree-untracked.sh:13-24,58`, `scripts/link-worktree-untracked.sh:124-158`, issue #296, PR #304, issue #318, issue #374

## 統合ポイント

- 呼び出し元: `commands/work-multi.md` Step 0.3
- 呼び出すもの: `hooks/lib/session-paths.sh`、`git status`、`git check-ignore`、`ln`、`uv`（利用可能な場合）、`python3 -m venv`（フォールバック）
- manifest の利用元: `commands/work.md` G-2、`commands/task.md` Phase 2
- CI: `.github/workflows/shellcheck.yml` が `*.sh` として lint する

## 注意事項・既知の制限

- lazy link した `node_modules` 等へ複数 worktree session が同時に書き込むと衝突し得る。
- `link` は安全に上書きできない既存 path や source 上の tracked/unavailable path を失敗として扱う。次の path を推測して続行しない。
- `venv` サブコマンドは対象 repository の `.gitignore` に venv/.venv 相当のパターンが無い場合は失敗する。linker が `.gitignore` を自動編集することはない（ユーザーの `.gitignore` を無断で書き換えないため）。
- `venv` サブコマンドは `uv`・`python3` のいずれも利用できない環境では失敗する（`python3` は repo 側の `external_cli_deps` に既定で含まれる想定）。

## 変更履歴（git log より自動生成）

- 5f7ba97 feat(#328): add lazy worktree linker
- 1aa3c2d fix(#318): distinguish worktree-untracked symlinks from real changes via manifest
- 69c1e80 fix(#296): use worktree- prefix only for branch classification and NUL-delimited untracked enumeration
- bc4ae7b feat(#296): add /work-multi worktree-isolated entry point
