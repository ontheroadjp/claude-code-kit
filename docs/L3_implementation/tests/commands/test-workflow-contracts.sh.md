# `tests/commands/test-workflow-contracts.sh`

## 目的・役割

docs-sync/init-docs/task/git-pr の既存境界に加え、unified `/work` entry と ordinary/delegated `/task` の共有契約を固定文字列で検証する。

## 動作の概要

既存 HARD STOP recovery、thread rename、Ready PR publication assertionsを維持し、`/work` の preflight-before-mutation、task-manager delegation、post-delegation cleanup、shared task implementation contractを追加検証する。

根拠: `tests/commands/test-workflow-contracts.sh:1-82`

## 統合ポイント

- targets: `commands/work.md`, `commands/task.md`, `commands/docs-sync.md`, `commands/init-docs.md`, `commands/patch.md`, `commands/git-pr.md`

## 注意事項

固定文字列による責務境界testであり、GitHub操作は実行しない。
