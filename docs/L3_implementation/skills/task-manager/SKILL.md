# `skills/task-manager/SKILL.md`

## 目的・役割

Codexがユーザーから `/task-manager` を要求されたときに、独立batch workflowのsource of truthである `commands/task-manager.md` を読み、その仕様を省略せず実行するためのskill entry pointである。

根拠: `skills/task-manager/SKILL.md:1-10`

## 動作の概要

1. `commands/task-manager.md` を完全に読む。
2. accepted issueごとに1つの実 `task-worker` sub-agentを使用する。
3. worker数は最大3とする。
4. sub-agent model overrideを指定せず親modelを継承する。
5. 既存implementation/documentation workflowから独立させる。
6. source of truthを独自解釈、簡略化、他workflowと統合しない。

根拠: `skills/task-manager/SKILL.md:12-19`

## 重要な設計判断

`task-worker`を独立commandやskillとして公開せず、親commandが起動payloadで役割を注入する。これにより、approved plan、worktree、branch、batch位置を持たないworkerの単独誤実行を防ぐ。

modelをskill内で固定しないため、workerは親agentと同じmodelを使い、runtimeごとのmodel availabilityに依存しない。

根拠: `skills/task-manager/SKILL.md:16-18`, `skills/task-manager/SKILL.md:21-25`

## 統合ポイント

- source of truth: `commands/task-manager.md`
- installer: `install.sh` が `skills/*/` を自動列挙し、skill directoryをsymlinkする
- test: `tests/commands/test-task-manager.sh`

## 注意事項・既知の制限

- command sourceがmissingまたはunreadableならworkflowを実行しない。
- skill自体からcommand sourceを編集しない。
- `task-worker`はuser-facing entry pointではない。

根拠: `skills/task-manager/SKILL.md:21-25`

## 変更履歴（git log より自動生成）

- 9ef8e99 feat(#377): add independent task manager workflow
