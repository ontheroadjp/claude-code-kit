# `tests/commands/test-task-manager.sh`

## 目的・役割

`commands/task-manager.md`と`skills/task-manager/SKILL.md`のbatch executor契約を固定文字列で検証するshell contract testである。

根拠: `tests/commands/test-task-manager.sh:1-50`

## 動作の概要

入力境界、read-only preflight、combined plan gate、real task-worker、complete Draft set approval、approved-head delegated context、input-order `/git-pr-merge` delegation、A/M/D/R documentation handling、partial recovery、completion comments、initial operational constraintsを検証する。

根拠: `tests/commands/test-task-manager.sh:52-132`

## 主要な検証契約

- 1〜3 issue、重複・4件以上・不正形式拒否
- plan approval前のmutation禁止
- real task-worker、最大3、親model継承、primary implementation commit と type・目的を揃えた Conventional Commit 形式の Draft source PR title（commit 数非依存）
- complete Draft setでhead SHA、scope/behavior、validation planを固定
- source PRをinput orderで `/git-pr-merge`へ委譲
- embedded latest-main/conflict/merge mechanicsのabsence
- unknown commitとmaterial changeのPR単位再承認
- rollback-capable batch transactionのabsenceとcompleted/pending reporting
- Added/Modified/Deleted/Renamed L3 handling
- documentation incomplete時のstandalone `/init-docs` recovery
- completion comment実行stepとmanual follow-up

根拠: `tests/commands/test-task-manager.sh:52-123`

## 重要な設計判断

single-PR deliveryの詳細は `test-git-pr-merge.sh`へ移し、このtestはtask-managerが完全なdelegated contextを渡し、state machineを重複させないorchestration boundaryを検証する。

## 統合ポイント

- targets: `commands/task-manager.md`, `skills/task-manager/SKILL.md`
- related delivery test: `tests/commands/test-git-pr-merge.sh`
- execution: `bash tests/commands/test-task-manager.sh`
- lint: `shellcheck -x tests/commands/test-task-manager.sh`

## 注意事項・既知の制限

sub-agent schedulingやGitHub mergeを実行するend-to-end testではなく、static workflow contract testである。

## 変更履歴（git log より自動生成）

- 57dce6c feat(#389): add reviewed PR delivery workflow
- 6dc29d5 #387 Simplify task-manager source delivery (#388)
- b2b83ac #384 Replace task-manager pre-integration with sequential PR refresh (#385)
- 823f676 #381 Align task-manager source PR titles with work (#382)
- 8a9903f #379 Reuse task-manager integration conflict resolutions (#380)
- 5f1d984 #377 Add independent task-manager batch workflow (#378)
