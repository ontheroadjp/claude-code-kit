# `skills/git-pr-merge/SKILL.md`

## 目的・役割

Codexが `/git-pr-merge` を直接要求された場合、または `/task-manager` からdelegated contextを受けた場合に、`commands/git-pr-merge.md`を完全に読み実行する薄いskill wrapperである。

根拠: `skills/git-pr-merge/SKILL.md:1-18`

## 動作の概要

- installed source of truth `~/.codex/commands/git-pr-merge.md`を指す。
- standalone approvalとdelegated approvalの区別を保つ。
- local main fallbackを禁止し、approved headなしのmergeを拒否する。
- cleanupをcallerへ残す。

根拠: `skills/git-pr-merge/SKILL.md:8-25`

## 重要な設計判断

deliveryロジックをskillへ複製せずcommand specificationへ一元化する。これによりClaude CodeとCodexが同じ承認・workspace・validation契約を共有する。

## 統合ポイント

- source of truth: `commands/git-pr-merge.md`
- delegated caller: `commands/task-manager.md`
- installer: `install.sh` の `skills/*/` 自動列挙
- test: `tests/commands/test-git-pr-merge.sh`

## 注意事項・既知の制限

command sourceがmissing/unreadableならworkflowを実行しない。
