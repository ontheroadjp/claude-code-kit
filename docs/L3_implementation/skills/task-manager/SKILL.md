# `skills/task-manager/SKILL.md`

## 目的・役割

`/work` から valid handoff を受けた場合だけ、2〜3件の delegated task workers を管理する internal batch orchestrator adapter。

## 動作の概要

1. command sourceを完全に読む。
2. `/work` の accepted issue と complete project context がなければ停止する。
3. 最大3つのreal workerへ delegated `commands/task.md` を実行させる。
4. issueごとのplan/Ready PR approvalを独立させる。
5. deliveryをinput orderで `/git-pr-merge`へ委譲する。
6. completion/failure/worktree stateを `/work`へ返し、cleanup/stashを所有しない。

根拠: `skills/task-manager/SKILL.md:1-30`

## 重要な設計判断

skillは `/work` と `/task` のlogicを複製せず、worker continuity、non-blocking approval、fixed-order delivery、cleanup return boundaryだけを固定する。

## 統合ポイント

- source: `commands/task-manager.md`
- worker: `commands/task.md`
- delivery: `commands/git-pr-merge.md`
- caller: `commands/work.md`

## 注意事項

standalone entry ではなく、task-workerも公開しない。
