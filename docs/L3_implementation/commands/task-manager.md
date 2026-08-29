# `commands/task-manager.md`

## 目的・役割

`/work` が validation 済みの2〜3 issue を渡した場合だけ動作する internal batch orchestrator。delegated `/task` workers の lifecycle と independent approvals を管理し、delivery のみ入力順に直列化する。

根拠: `commands/task-manager.md:1-18`

## 動作の概要

1. `/work` から accepted issue metadata、complete project context、base SHA、workspace/stash ownership を受け取る。
2. issue ごとの isolated worktree と real worker を作り、worker に `commands/task.md` delegated mode を実行させる。
3. plan と Ready PR を到着順に個別承認へ relay し、unrelated worker は継続させる。
4. approved PR を input order で `/git-pr-merge` に渡す。
5. completion/failure、head、PR、validation、remaining worktree を `/work` へ返す。

根拠: `commands/task-manager.md:6-131`

## 主要な判定ロジック

- payload が不完全なら mutation せず failure を返す。
- issue state は `investigating`、`awaiting_plan_approval`、`implementing`、`awaiting_pr_approval`、`delivery_eligible`、`delivering`、`completed`、`failed`。
- `MAX_TASK_WORKERS = 3`、worker model override なし。
- delivery は先行 issue が completed のときだけ進む。
- mechanical latest-main/docs refresh は再承認不要だが、behavior・contract・design/security・scope・unknown diff の変更は対象 PR だけ再承認する。

根拠: `commands/task-manager.md:16-29`, `commands/task-manager.md:70-113`

## 重要な設計判断

- `/work` 相当の preflight/project investigation と `/task` 相当の実装・docs・PR contract を削除し、reasoning と workflow definition の重複を避ける。
- worker は既存 `/task` の delegated mode を完全に実行し、Draft-only な独自 pipeline を持たず Ready PR を返す。
- parent workspace と stash は session owner `/work` に残し、orchestrator は cleanup candidate の報告だけを行う。

## 統合ポイント

- caller/session owner: `commands/work.md`
- worker contract: `commands/task.md`
- delivery: `commands/git-pr-merge.md`
- adapter: `skills/task-manager/SKILL.md`

## 注意事項・既知の制限

- standalone invocation は required handoff がないため `/work #x #y` を案内して終了する。
- cross-session resume、distributed lock、persistent batch state、final batch docs PR は持たない。

## 変更履歴（git log より自動生成）

- f52dd59 feat(#400): unify work entry point
- 05fbd40 fix(#398): preserve task-manager test executable mode
- f3be053 feat(#398): stream task-manager issue pipelines
- a23fda3 #389 Add reusable reviewed PR delivery workflow (#391)
