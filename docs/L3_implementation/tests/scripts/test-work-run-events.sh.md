# `tests/scripts/test-work-run-events.sh`

## 目的・役割

writerのrun/session correlation、並列追記、sequence、privacy allowlist、fail-open、run ID path safetyを検証するshell test。

## 動作の概要

isolated session/log rootでparent start、worker attach、20並列emitを実行する。連番・共通run ID・複数sessionを検証し、未知keyとpath traversal run IDをstrict modeで拒否する。

根拠: `tests/scripts/test-work-run-events.sh:1-65`

## 統合ポイント

- target: `scripts/work-run-events.sh`
- tools: Bash, jq

## 注意事項

test用log rootを使いproduction logsへ書き込まない。

## 変更履歴（git log より自動生成）

- 5f3aacf feat(#401): add structured work run observability
