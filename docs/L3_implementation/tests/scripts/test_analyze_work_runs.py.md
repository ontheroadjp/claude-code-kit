# `tests/scripts/test_analyze_work_runs.py`

## 目的・役割

analyzerのstatus inference、session correlation、duration/parallel metrics、invalid JSON handlingを検証するpytest suite。

## 動作の概要

synthetic JSONLからsuccess、gate-stopped、partial-failure、interrupted、parse-error incompleteを構成し、issue/session listsと各metricsを検証する。

根拠: `tests/scripts/test_analyze_work_runs.py:1-100`

## 統合ポイント

- target: `scripts/analyze_work_runs.py`
- runner: pytest

## 注意事項

実際のrepository logsやagent transcriptsを使わない。
