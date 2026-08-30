# `commands/task-manager.md`

## 目的・役割

`/work` が validation 済みの2〜3 issue を渡した場合だけ動作する internal batch orchestrator。delegated `/task` workers の lifecycle と independent approvals を管理する。worker は入力順に**完全直列**で1件ずつ処理し、investigation・planning・実装・delivery のすべてが直列で、同時に active な worker は常に1つである。

根拠: `commands/task-manager.md:1-33`

## 動作の概要

1. `/work` から accepted issue metadata、complete project context、base SHA、workspace/stash ownership を受け取る。
2. accepted issue を入力順に1件ずつ処理する。各 `#k` について、共有 working tree を latest `origin/main`（`#(k-1)` の squash commit を含む）へ fast-forward し、その SHA を `Base SHA` として real `task-worker` sub-agent 1つに渡し、解決済み絶対パス（`Command root`・`Work-run events helper`・`L3 doc root`）とともに `<Command root>/task.md` delegated mode を実行させる。
3. plan・実装レビュー・Ready PR を到着順に issue 単独で承認へ relay し、複数 issue の gate を束ねて提示せず、1 プロンプト＝1 issue の問いにする。plan 承認で即実装、PR 承認で `delivery_eligible`。
4. approved PR を `/git-pr-merge` に渡して delivery する。`#k` は `#(k-1)` を含む latest `origin/main` から分岐しているため、latest-main refresh は通常 no-op か clean fast-forward になる。
5. `#k` が `completed` になってから `#(k+1)` の worker を起動する。
6. completion/failure、head、PR、validation、remaining worktree を `/work` へ返す。
7. worker が返した SHA-bound full-suite evidence（全 worker が issue につき1回返す。base は latest `origin/main`）は完全性と Ready PR head の一致だけを確認して保持し、reuse policy を解釈せず `/git-pr-merge` へ転送する。

根拠: `commands/task-manager.md:1-155`

## 主要な判定ロジック

- payload が不完全なら mutation せず failure を返す。
- issue state は `investigating`、`awaiting_plan_approval`、`implementing`、`awaiting_pr_approval`、`delivery_eligible`、`delivering`、`completed`、`failed`。同時に active な worker は1つだけで、`#(k+1)` は `#k` が `origin/main` に squash merge されて `completed` になるまで起動しない。
- `MAX_TASK_WORKERS = 1`（同時実行数）。1 batch の issue 数は2〜3。worker model override なし。
- worker payload は `task.md`・`coding-*.md`・`work-run-events.sh` の解決済み絶対パスを運ぶ。worker は cwd 相対解決やファイルシステム探索をせず payload パスから読む（worker cwd はターゲットレポの working tree で、toolkit レポの `commands/` は相対解決できないため）。
- **per-issue worktree を作らない。** 同時に実装する issue が1件のため、delegated worker は ordinary `/task` と同じく共有 working tree 上で作業ブランチ `feat/<issue-number>-<slug>` を作成する。branch は worker が plan 承認後に作り、task-manager は事前作成しない。branch の付け替え（`reset` 等 rewriting）もしない。
- approval relay は非バッチ（必須）。ready handoff を他 issue と揃える目的で保留せず、複数 issue の plan・実装レビュー・PR gate を1プロンプトに束ねず、1 issue ずつ承認・却下・修正指示を受ける。
- cross-issue の待ちは1つだけ: `#(k+1)` の worker 起動 = `#k` の delivery 完了。それ以外の gate は対象 issue の handoff 到着だけで進む。
- worker message 待機中は状態遷移のない進捗ナレーションを新ターンとして出さず、単一の長い wait で実 message / 必須 gate 到来時のみ発話する。
- delivery は先行 issue が completed のときだけ進む（batch は1 issue ずつ進むため in-flight PR は常に1本）。
- validation evidence の生成・補完・再利用判定は行わない。evidence がなくても PR approval と delivery は継続し、authoritative fallback は `/git-pr-merge` に委ねる。

根拠: `commands/task-manager.md:23-46`, `commands/task-manager.md:97-133`

## 重要な設計判断

- `/work` 相当の preflight/project investigation と `/task` 相当の実装・docs・PR contract を削除し、reasoning と workflow definition の重複を避ける。
- #412 の「approved-head chain」（`#k` が `#(k-1)` の squash 前 approved PR head を `git merge` で内包）を撤回し、`#k` を `#(k-1)` が squash 済みの latest `origin/main` から分岐させる完全直列モデルへ移行した。実測バッチで、squash commit と approved head が git から分岐履歴として見えるため delivery のたびに merge conflict が発生し、削除したはずの conflict-repair 経路に依存していた（issue #414）。fresh base では分岐履歴そのものが存在しないため conflict は外部変更時のみになる。
- 同時に実装する issue が1件だけなので per-issue worktree は不要。delegated worker は ordinary `/task` と同じく共有 working tree でブランチを切り替える。worktree 作成・untracked/venv symlink 注入・`.claude/worktrees/` 管理が消える。並行セッションは従来どおり `/work-multi` が全体を1 worktree に包む。
- full-suite evidence は全 worker が凍結された base（latest `origin/main`）上で結合状態を issue につき1回検証する。`/git-pr-merge` は #404 の厳密な head/base/plan SHA 一致を満たす場合にだけ再利用する。
- worker は既存 `/task` の delegated mode を完全に実行し、Draft-only な独自 pipeline を持たず Ready PR を返す。
- parent workspace と stash は session owner `/work` に残し、orchestrator は cleanup candidate の報告だけを行う。
- validation reuse decision を delivery owner に局所化し、task-manager は orchestration-focused handoff のまま保つ。

## 統合ポイント

- caller/session owner: `commands/work.md`
- worker contract: `commands/task.md`
- delivery: `commands/git-pr-merge.md`
- full-suite evidence producer: 全 delegated `commands/task.md` worker（issue につき1回、latest `origin/main` 上で）
- adapter: `skills/task-manager/SKILL.md`

## 注意事項・既知の制限

- standalone invocation は required handoff がないため `/work #x #y` を案内して終了する。
- 完全直列のため、3 issue バッチの wall time は概ね 1 issue の 3 倍。並行による短縮はしない。
- cross-session resume、distributed lock、persistent batch state、final batch docs PR は持たない。

## 変更履歴（git log より自動生成）

- dcfb4af refactor(#414): replace the task-manager approved-head chain with fully-serial, worktree-free implementation
- 118ab35 feat(#412): chain delegated task-manager workers on the predecessor approved PR head (#413)
- abe4573 feat(#410): consolidate the shared work-run event contract into work.md (#411)
- ff0872c feat(#408): carry resolved command and helper paths in worker payload (#409)
- 3a2f223 feat(#406): forbid batching approval gates across task-manager issues (#407)
- 29b88f2 feat(#404): reuse SHA-bound full-suite validation (#405)
- 9fc5b9a feat(#401): add structured work run observability (#403)
- 72a11b5 feat(#400): unify work entry point (#402)
- b3d7d3b feat(#398): stream task-manager issue pipelines (#399)
- a9fbb5f fix(#369): generate conventional task PR titles (#395)

## Work-run observability

共有契約は `commands/work.md`「Work-run observability › 共有契約」を参照し再記述しない。親 `/work` から `work_run_id` を受け取りworkerへ伝播し、`worker_registered`・issue state・plan/PR approval wait・`approved_head_recorded` を、それぞれの既存state transitionのownerがemitする。telemetry用の別state machineは持たない。

根拠: `commands/task-manager.md`（worker lifecycle, approval relay）
