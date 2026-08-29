# `tests/commands/test-task-manager.sh`

## 目的・役割

`/work`・`/task`・`/task-manager` と3つの skill adapters の unified entry contract を固定文字列で検証する shell contract test。

## 動作の概要

- `/work` の multi-input、atomic preflight、one-time context、single/multi routing、cleanup ownershipを検証する。
- `/task` の shared delegated mode、supplemental investigation、same-worker continuity、Ready PR handoffを検証する。
- `/task-manager` が preflight/project investigation/PR creationを複製せず、independent stateとfixed-order deliveryだけを持つことを検証する。
- skill adapters が同じ ownership boundaryを保持することを検証する。

根拠: `tests/commands/test-task-manager.sh:1-103`

## 重要な設計判断

orchestratorだけでなく3 workflow間のabsence contractも検証し、旧来のDraft PR pipelineやduplicated parent investigationの再導入を防ぐ。

## 統合ポイント

- targets: `commands/work.md`, `commands/task.md`, `commands/task-manager.md`
- related: `tests/commands/test-workflow-contracts.sh`, `tests/commands/test-git-pr-merge.sh`

## 注意事項

static Markdown contract testであり、real workersやGitHub PRを起動しない。

## 変更履歴（git log より自動生成）

- f52dd59 feat(#400): unify work entry point
- b3d7d3b feat(#398): stream task-manager issue pipelines (#399)
- a9fbb5f fix(#369): generate conventional task PR titles (#395)
- a23fda3 #389 Add reusable reviewed PR delivery workflow (#391)

## Work-run coverage

task-managerが親 `work_run_id`、issue-specific approval wait、approved head correlationを保持することを固定文字列で検証する。

根拠: `tests/commands/test-task-manager.sh:80-82`
