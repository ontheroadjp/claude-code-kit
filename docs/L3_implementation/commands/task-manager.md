# `commands/task-manager.md`

## 目的・役割

`/work` が validation 済みの2〜3 issue を渡した場合だけ動作する internal batch orchestrator。delegated `/task` workers の lifecycle と independent approvals を管理し、delivery のみ入力順に直列化する。

根拠: `commands/task-manager.md:1-18`

## 動作の概要

1. `/work` から accepted issue metadata、complete project context、base SHA、workspace/stash ownership を受け取る。
2. issue ごとの isolated worktree と real worker を作り、worker payload に解決済み絶対パス（`Command root`＝実行 agent の installed commands dir、`Work-run events helper`＝同 `work-run-events.sh`、`L3 doc root`）を載せて `<Command root>/task.md` delegated mode を実行させる。
3. plan・実装レビュー・Ready PR を到着順に issue 単独で承認へ relay し、unrelated worker は継続させる。複数 issue の gate を束ねて提示せず、1 プロンプト＝1 issue の問いにする。
4. approved PR を input order で `/git-pr-merge` に渡す。
5. completion/failure、head、PR、validation、remaining worktree を `/work` へ返す。
6. worker が返した optional SHA-bound full-suite evidence は完全性と Ready PR head の一致だけを確認して保持し、reuse policy を解釈せず `/git-pr-merge` へ転送する。

根拠: `commands/task-manager.md:6-143`

## 主要な判定ロジック

- payload が不完全なら mutation せず failure を返す。
- issue state は `investigating`、`awaiting_plan_approval`、`implementing`、`awaiting_pr_approval`、`delivery_eligible`、`delivering`、`completed`、`failed`。
- `MAX_TASK_WORKERS = 3`、worker model override なし。
- worker payload は `task.md`・`coding-*.md`・`work-run-events.sh` の解決済み絶対パスを運ぶ。worker は cwd 相対解決やファイルシステム探索をせず payload パスから読む（worker cwd はターゲットレポの worktree で、toolkit レポの `commands/` は相対解決できないため）。
- approval relay は非バッチ（必須）。ready handoff を他 issue と揃える目的で保留せず、複数 issue の plan・実装レビュー・PR gate を1プロンプトに束ねず、1 issue ずつ承認・却下・修正指示を受ける。
- cross-issue の順序待ちは Phase 3 fixed-order delivery のみ。それ以前の各 gate は対象 issue の handoff 到着だけで進む。
- worker message 待機中は状態遷移のない進捗ナレーションを新ターンとして出さず、単一の長い wait で実 message / 必須 gate 到来時のみ発話する。
- delivery は先行 issue が completed のときだけ進む。
- mechanical latest-main/docs refresh は再承認不要だが、behavior・contract・design/security・scope・unknown diff の変更は対象 PR だけ再承認する。
- validation evidence の生成・補完・再利用判定は行わない。evidence がなくても PR approval と delivery は継続し、authoritative fallback は `/git-pr-merge` に委ねる。

根拠: `commands/task-manager.md:16-29`, `commands/task-manager.md:82-121`

## 重要な設計判断

- `/work` 相当の preflight/project investigation と `/task` 相当の実装・docs・PR contract を削除し、reasoning と workflow definition の重複を避ける。
- worker は既存 `/task` の delegated mode を完全に実行し、Draft-only な独自 pipeline を持たず Ready PR を返す。
- parent workspace と stash は session owner `/work` に残し、orchestrator は cleanup candidate の報告だけを行う。
- validation reuse decision を delivery owner に局所化し、task-manager は orchestration-focused handoff のまま保つ。

## 統合ポイント

- caller/session owner: `commands/work.md`
- worker contract: `commands/task.md`
- delivery: `commands/git-pr-merge.md`
- optional evidence producer: delegated `commands/task.md` merge position `1/<batch size>` worker
- adapter: `skills/task-manager/SKILL.md`

## 注意事項・既知の制限

- standalone invocation は required handoff がないため `/work #x #y` を案内して終了する。
- cross-session resume、distributed lock、persistent batch state、final batch docs PR は持たない。

## 変更履歴（git log より自動生成）

- 3aff0cc feat(#410): consolidate the shared work-run event contract into work.md
- ff0872c feat(#408): carry resolved command and helper paths in worker payload (#409)
- 3a2f223 feat(#406): forbid batching approval gates across task-manager issues (#407)
- 29b88f2 feat(#404): reuse SHA-bound full-suite validation (#405)
- 9fc5b9a feat(#401): add structured work run observability (#403)
- 72a11b5 feat(#400): unify work entry point (#402)
- b3d7d3b feat(#398): stream task-manager issue pipelines (#399)
- a9fbb5f fix(#369): generate conventional task PR titles (#395)
- a23fda3 #389 Add reusable reviewed PR delivery workflow (#391)
- 6dc29d5 #387 Simplify task-manager source delivery (#388)

## Work-run observability

共有契約は `commands/work.md`「Work-run observability › 共有契約」を参照し再記述しない。親 `/work` から `work_run_id` を受け取りworkerへ伝播し、`worker_registered`・issue state・plan/PR approval wait・`approved_head_recorded` を、それぞれの既存state transitionのownerがemitする。telemetry用の別state machineは持たない。

根拠: `commands/task-manager.md`（worker lifecycle, approval relay）
