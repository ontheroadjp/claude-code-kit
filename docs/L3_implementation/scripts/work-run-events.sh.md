# `scripts/work-run-events.sh`

## 目的・役割

1回のlogical `/work` とdelegated workersが所有するsemantic lifecycle eventを `logs/work-runs/<YYYY-MM>/<work_run_id>.jsonl` へbest-effortで記録する共有CLI。

## 動作の概要

- `start`: 24桁hex run IDを生成しsession contextへ保存する。
- `attach`: 親run IDをworker sessionへ関連付ける。
- `emit`: 固定schemaで検証したeventを追記する。
- `current`: sessionのrun IDを返す。

lock directoryでsequence採番と追記を直列化する。通常modeはfail-open、test用 `--strict` だけがschema/IO failureを非ゼロで返す。

根拠: `scripts/work-run-events.sh:1-270`

## 重要な設計判断

prompt、response、diff、source、tool output、自由記述を受け付けない。既存telemetryは複製せず、共通resolverの `agent_session_id` でjoinする。

## 統合ポイント

- callers: work/task-manager/task/docs-sync/git-pr/git-pr-merge command specs
- session resolver: `hooks/lib/session-id.sh`
- analyzer: `scripts/analyze_work_runs.py`
- approval shape: `hooks/auto-approve-readonly.sh`

## 注意事項・既知の制限

強制終了で終端eventが欠けてもworkflow本体は継続し、analyzerがinterruptedとして分類する。

## 変更履歴（git log より自動生成）

- 5f3aacf feat(#401): add structured work run observability
