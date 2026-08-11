# `commands/work-multi.md`

## 目的・役割

意図的な並行セッション利用向けに、`commands/work.md` と全く同じワークフローを `EnterWorktree` で作成した専用 worktree 内で実行するエントリポイント（issue #296）。共有 working tree での `git checkout` 衝突（`/work #283` で実際に発生、project memory に記録）を、working tree の物理的分離によって防ぐ。

根拠: `commands/work-multi.md:1-7`

## 動作概要

Step 0 で (1) `pwd` を記録し、(2) `EnterWorktree`（`path` 指定なし）で新規 worktree に切り替え、(3) `scripts/link-worktree-untracked.sh` を実行して untracked ファイル/ディレクトリを symlink する。Step 1 で `commands/work.md` を Read し、一字一句そのまま実行する。`commands/work.md` 自体のゲート・ルーティングロジックはここでは重複定義しない。

根拠: `commands/work-multi.md:9-41`

## 重要な設計判断

- `commands/work.md` を丸ごとコピーせず Read して委譲する薄いラッパー構成とした。`skills/work/SKILL.md` が `commands/work.md` に対して既に採用している「単一 source of truth への薄いポインタ」パターンを踏襲し、`work.md` 変更のたびに二重メンテナンスが発生するリスクを避けるため。
- untracked ファイル/ディレクトリの symlink は当初のスコープになかったが、実装時の検証で必要と判明した（issue #296 参照）。`git worktree add`（`EnterWorktree` の内部実装）は tracked ファイルのみをチェックアウトし、untracked/gitignored ファイルはコピーしない。この toolkit は特定プロジェクト専用ではなく任意のリポジトリで使う実行環境基盤であるため、対象リポジトリ固有の untracked パスを個別に把握することはできず、`.git`・`.claude` を除く全ての untracked/ignored パスを一律で symlink する汎用方針とした。
- `.claude` を丸ごと除外したのは、`EnterWorktree` 自身が worktree を `.claude/worktrees/<name>` 配下に作成する固定仕様のため。`.claude` を symlink すると、新しい worktree の中に worktrees ディレクトリ自身への自己参照ループが生じる。副作用として worktree は `.claude/settings.local.json`（ローカル権限設定）を引き継がない（安全側＝確認プロンプト増加の方向のみ）。
- node_modules 等セッション中に書き換わる依存ディレクトリも一律 symlink の対象に含まれる。これは worktree 隔離の目的（共有可変状態の衝突防止）と部分的に矛盾するトレードオフだが、対象リポジトリ非依存の汎用実装を優先し、既知の限界として `CLAUDE.md` に文書化するに留めた（リポジトリごとの依存ディレクトリ名を個別に除外するとリポジトリ固有の特別扱いが必要になり、この toolkit の汎用性の前提と矛盾するため）。
- `ExitWorktree` は明示的なユーザー指示がない限り呼ばない。セッション終了時の keep/remove 確認は harness の既存機能に委ねる。
- symlink 化した untracked/ignored パスは `.gitignore` のディレクトリ限定パターン（末尾 `/`）に一致せず `git status` に `??`/`!!` として現れる（実機で `ExitWorktree` が無害な symlink を「未コミットの変更」として検出し `discard_changes` を要求する事例で発覚。issue #318）。git 側の ignore 判定を変える案（`extensions.worktreeConfig` + 各 worktree 専用 `core.excludesFile`）を実機検証し機能することを確認したが、目的は「git status を完全にクリーンにする」ことではなく「予期しない untracked ファイルを見た際に無駄な調査（`ls -la`・`readlink` 等）をせず即座に判別できる」ことであるため、git 設定を変更しないスコープの小さい manifest 方式（`scripts/link-worktree-untracked.sh` が symlink 化したパス一覧を session tmp directory に書き出し、`commands/work.md` G-2・`commands/task.md` Phase 2 が突き合わせる）を採用した。`ExitWorktree` 自体の判定（harness 機能のため変更不可）は変わらないが、manifest と突き合わせれば既知のものと即座に判別できる。

根拠: `commands/work-multi.md:23-35`, `commands/work-multi.md:48-50`, issue #296, issue #318

## 統合ポイント

- 委譲先: `commands/work.md`（無改変のまま Read して実行）
- 利用ツール: `EnterWorktree`（`.claude/worktrees/<name>` に `origin/<default-branch>` から分岐した `worktree-<name>` ブランチを作成）
- 補助スクリプト: `scripts/link-worktree-untracked.sh`

## 注意事項・既知の制限

- 既存 worktree への再入場（`EnterWorktree` の `path` 引数）はスコープ外。常に新規 worktree を作成する。
- `site/node_modules` 等の依存ディレクトリが symlink 経由で複数 `/work-multi` セッション間に共有されるため、同じ依存ディレクトリを持つセッションでパッケージマネージャの書き込み操作を同時実行しないこと（`CLAUDE.md` に既知の限界として記載）。

## 変更履歴（git log より自動生成）

- bc4ae7b feat(#296): add /work-multi worktree-isolated entry point
