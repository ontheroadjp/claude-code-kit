# `skills/task-manager/SKILL.md`

## 目的・役割

Codexが `/task-manager` を要求されたとき、`commands/task-manager.md`を完全に読み、streaming issue pipelineをそのまま実行させるskill entry pointである。

根拠: `skills/task-manager/SKILL.md:1-15`

## 動作の概要

1. command sourceを完全に読む。
2. accepted issueごとに最大3つのreal task-workerを使い、親modelを継承する。
3. complete structured parent investigation handoffをworkerへ渡す。
4. issueごとのplan/PR approvalを独立させ、approval waitでunrelated workerを止めない。
5. issue-required documentationを同じPRへ含め、final batch documentation PRを作らない。
6. deliveryをuser-provided orderで `/git-pr-merge`へ委譲する。

根拠: `skills/task-manager/SKILL.md:12-22`

## 重要な設計判断

skillはworkflow logicを複製せず、worker continuity、non-blocking approval、fixed-order delivery、per-PR documentationという重要なorchestration boundaryだけを固定する。internal task-workerはuser-facing commandにしない。

## 統合ポイント

- source of truth: `commands/task-manager.md`
- delivery dependency: `commands/git-pr-merge.md`
- installer: `install.sh`
- test: `tests/commands/test-task-manager.sh`

## 注意事項・既知の制限

- task-workerをstandalone command/skillとして公開しない。
- command sourceがmissing/unreadableなら実行しない。

## 変更履歴（git log より自動生成）

- 57dce6c feat(#389): add reviewed PR delivery workflow
- 5f1d984 #377 Add independent task-manager batch workflow (#378)
