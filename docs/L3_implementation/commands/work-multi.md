# `commands/work-multi.md`

## 目的・役割

意図的な並行セッション利用向けに、`commands/work.md` と全く同じワークフローを `EnterWorktree` で作成した専用 worktree 内で実行するエントリポイント（issue #296）。共有 working tree での `git checkout` 衝突（`/work #283` で実際に発生、project memory に記録）を、working tree の物理的分離によって防ぐ。

根拠: `commands/work-multi.md:1-7`

## 動作概要

Step 0 で (1) `pwd` を `ORIGINAL_WORKDIR` として記録し、(2) `EnterWorktree`（`path` 指定なし）で新規 worktree に切り替え、(3) installer が agent 別に配布した `link-worktree-untracked.sh` の `prepare` に元 worktree を渡して lazy linker を初期化する。`ORIGINAL_WORKDIR` はこの `prepare` 引数専用であり、切り替え後の Read・現状調査・Git 操作では新しい worktree を CWD のまま使用する。共有 checkout への `cd` や `git -C "$ORIGINAL_WORKDIR"` は行わない。Claude Code は `~/.claude/scripts/link-worktree-untracked.sh`、Codex CLI は `~/.codex/scripts/link-worktree-untracked.sh` を使う。

issue 番号が親 issue を指す場合は Step 1 で実装対象を決定する。native `subIssues` と、既存の未完了 task list に列挙された子 issue を収集し、子 issue ごとの native `blockedBy` dependency を読む。`OPEN` で全 blocker が `CLOSED` の子だけを実装可能とし、複数なら収集順で最初の 1 件を選ぶ。候補がない、または GitHub の取得・dependency 情報が利用できないときは、推測せず理由を報告して終了する。親に子 issue がなければ従来どおり指定 issue を使う。選ばれた子 issue 番号を、Step 2 で `commands/work.md` へ渡す。

Step 2 で `commands/work.md` を Read し、一字一句そのまま実行する。`commands/work.md` 自体のゲート・ルーティングロジックはここでは重複定義しない。

根拠: `commands/work-multi.md:9-50`

## 重要な設計判断

- `commands/work.md` を丸ごとコピーせず Read して委譲する薄いラッパー構成とした。`skills/work/SKILL.md` が `commands/work.md` に対して既に採用している「単一 source of truth への薄いポインタ」パターンを踏襲し、`work.md` 変更のたびに二重メンテナンスが発生するリスクを避けるため。
- 親 issue の子 issue 選択は `subIssues` と task list の両方を読む。既存の `/new-issue` が task list を親子追跡に用いているため、native sub-issue 専用にすると既存の親 issue を入口にできなくなる。一方で実装順の判断は GitHub の構造化された `blockedBy` だけに限定し、本文の自然言語を依存関係として推測しない。
- 複数の実装可能な子 issue は収集順で最初の 1 件を選ぶ。複数セッションで同じ親を指定しても選択根拠を再現可能にし、恣意的な優先順位付けを持ち込まないため。
- `ORIGINAL_WORKDIR` は lazy linker が元 worktree を特定するためだけに保持し、worktree 切り替え後の CWD としては使わない。共有 checkout へ移動して Git を実行すると worktree-isolation guard に拒否され、並行実行の分離保証も損なうため。
- `git worktree add`（`EnterWorktree` の内部実装）は tracked ファイルのみをチェックアウトするため、lazy linker は必要になった untracked/ignored path だけを symlink する。初期化時に大きな `node_modules` 等を処理せず、対象リポジトリ固有の path をあらかじめ仮定しない。
- `.claude` を丸ごと除外したのは、`EnterWorktree` 自身が worktree を `.claude/worktrees/<name>` 配下に作成する固定仕様のため。`.claude` を symlink すると、新しい worktree の中に worktrees ディレクトリ自身への自己参照ループが生じる。副作用として worktree は `.claude/settings.local.json`（ローカル権限設定）を引き継がない（安全側＝確認プロンプト増加の方向のみ）。
- node_modules 等セッション中に書き換わる依存ディレクトリも一律 symlink の対象に含まれる。これは worktree 隔離の目的（共有可変状態の衝突防止）と部分的に矛盾するトレードオフだが、対象リポジトリ非依存の汎用実装を優先し、既知の限界として `CLAUDE.md` に文書化するに留めた（リポジトリごとの依存ディレクトリ名を個別に除外するとリポジトリ固有の特別扱いが必要になり、この toolkit の汎用性の前提と矛盾するため）。
- `ExitWorktree` は明示的なユーザー指示がない限り呼ばない。セッション終了時の keep/remove 確認は harness の既存機能に委ねる。
- symlink 化した untracked/ignored パスは `.gitignore` のディレクトリ限定パターン（末尾 `/`）に一致せず `git status` に `??`/`!!` として現れる（実機で `ExitWorktree` が無害な symlink を「未コミットの変更」として検出し `discard_changes` を要求する事例で発覚。issue #318）。git 側の ignore 判定を変える案（`extensions.worktreeConfig` + 各 worktree 専用 `core.excludesFile`）を実機検証し機能することを確認したが、目的は「git status を完全にクリーンにする」ことではなく「予期しない untracked ファイルを見た際に無駄な調査（`ls -la`・`readlink` 等）をせず即座に判別できる」ことであるため、git 設定を変更しないスコープの小さい manifest 方式（`scripts/link-worktree-untracked.sh` が symlink 化したパス一覧を session tmp directory に書き出し、`commands/work.md` G-2・`commands/task.md` Phase 2 が突き合わせる）を採用した。`ExitWorktree` 自体の判定（harness 機能のため変更不可）は変わらないが、manifest と突き合わせれば既知のものと即座に判別できる。

根拠: `commands/work-multi.md:23-35`, `commands/work-multi.md:48-50`, issue #296, issue #318

## 統合ポイント

- GitHub: `gh issue view --json number,title,body,subIssues`、`gh issue view --json number,title,state,blockedBy`
- 委譲先: `commands/work.md`（親 issue の解決後、無改変のまま Read して実行）
- 利用ツール: `EnterWorktree`（`.claude/worktrees/<name>` に `origin/<default-branch>` から分岐した `worktree-<name>` ブランチを作成）
- 補助スクリプト: `install.sh` により `~/.claude/scripts/link-worktree-untracked.sh` または `~/.codex/scripts/link-worktree-untracked.sh` へ配布される `scripts/link-worktree-untracked.sh`

## 注意事項・既知の制限

- 既存 worktree への再入場（`EnterWorktree` の `path` 引数）はスコープ外。常に新規 worktree を作成する。
- `site/node_modules` 等の依存ディレクトリが symlink 経由で複数 `/work-multi` セッション間に共有されるため、同じ依存ディレクトリを持つセッションでパッケージマネージャの書き込み操作を同時実行しないこと（`CLAUDE.md` に既知の限界として記載）。
- 子 issue の本文に書かれた依存関係は対象にせず、GitHub native dependency のみを実装順の根拠にする。native dependency を取得できない環境では安全側で停止する。

## 変更履歴（git log より自動生成）

- 1453def fix(#330): preserve worktree isolation
- e624ef2 #328 Add lazy worktree linker (#329)
- ea565ac #326 Automate worktree symlink status filtering (#327)
- 4f4aab8 #324 Install the worktree linker for consumer repositories (#325)
- 1aa3c2d fix(#318): distinguish worktree-untracked symlinks from real changes via manifest
- bc4ae7b feat(#296): add /work-multi worktree-isolated entry point
