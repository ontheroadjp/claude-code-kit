# `skills/task-manager/SKILL.md`

## 目的・役割

Codexが `/task-manager` を要求されたとき、`commands/task-manager.md`を完全に読み、real `task-worker`と `/git-pr-merge` delegationを含むbatch executor workflowを実行するskill entry pointである。

根拠: `skills/task-manager/SKILL.md:1-19`

## 動作の概要

1. command sourceを完全に読む。
2. accepted issueごとに最大3つのreal `task-worker`を使う。
3. model overrideを省略して親modelを継承する。
4. source preparation/documentation finalizationは既存workflowから独立させる。
5. approved source PR deliveryだけを `commands/git-pr-merge.md`へ委譲する。

根拠: `skills/task-manager/SKILL.md:12-20`

## 重要な設計判断

internal task-workerをuser-facing commandにせず、single-PR deliveryだけを公開された再利用可能componentへ分離する。skill自体にはworkflow logicを複製しない。

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
