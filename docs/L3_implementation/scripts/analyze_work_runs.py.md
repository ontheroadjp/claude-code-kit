# `scripts/analyze_work_runs.py`

## 目的・役割

work-run JSONLをread-only集計し、run status、時間、parallel worker activity、issue/session correlationをJSON出力する。

## 動作の概要

sequence順にeventを読み、terminal event、gate stop、failed issue、終端欠落からstatusを分類する。elapsed、approval wait、PR preparation、delivery duration、parallel worker peakを算出する。invalid lineはcountしclean successをincompleteへ降格する。

根拠: `scripts/analyze_work_runs.py:1-230`

## 重要な設計判断

raw access/approval/token logは読まず、`agent_session_ids` を外部join keyとして返す。

## 統合ポイント

- producer: `scripts/work-run-events.sh`
- input: `logs/work-runs/**/*.jsonl`
- tests: `tests/scripts/test_analyze_work_runs.py`

## 注意事項・既知の制限

対にならないwait/start eventはdurationへ加算しない。
