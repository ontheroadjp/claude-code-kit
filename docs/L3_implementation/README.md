# `README.md`

## 目的・役割

repositoryの公開入口として、利用可能なcommand、installation、usage、local verification、設計原則、構造を一覧化する。

根拠: `README.md:1-167`

## 動作の概要

- Features tableで `/task-manager` をuser-provided batch executor、`/git-pr-merge` をreviewed PR delivery workflowとして公開する。
- Usageでstandalone PR deliveryとtask-managerからの逐次委譲を説明する。
- local verificationに両workflowのcontract testを掲載する。
- Design Principlesでapproved head SHA、owned PR worktree、current-head validation、explicit squash mergeの境界を固定する。

根拠: `README.md:5-35`, `README.md:88-116`, `README.md:120-145`, `README.md:147-157`

## 重要な設計判断

`/work`と`/task`はready PR作成で完了し、mergeは自動化しない。review後のdeliveryはユーザーが明示的に `/git-pr-merge` を起動する別責務とする。`/task-manager`だけはcomplete Draft set approvalをdelegated approval contextとして同workflowを利用する。

## 統合ポイント

- command specifications: `commands/*.md`
- Codex wrappers: `skills/*/SKILL.md`
- command tests: `tests/commands/*.sh`
- installer: `install.sh`

## 注意事項・既知の制限

READMEは概要であり、実行時の完全な安全条件は各command specificationをsource of truthとする。
