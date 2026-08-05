# hooks/log-token-usage.sh specification

## 目的・役割

Stop hook。transcript 全体を再集計し、セッションの累積トークン使用量・コスト・自身の実行時間を `logs/token-usage/*.log` へ1行追記する。`scripts/analyze_token_usage.py`（呼び出し元は `commands/analyze-token-usage.md`）がこのログを消費する。

根拠: `hooks/log-token-usage.sh:1-83`

## 動作の概要

1. スクリプト冒頭（`payload=$(cat)` より前）で `$EPOCHREALTIME` を `HOOK_START_TIME` として取得し、`hooks/lib/hook-timing.sh` を source する
2. stdin の hook payload から `transcript_path` / `session_id` を取り出す。`transcript_path` が空またはファイル不在なら何もせず終了する
3. `jq -rsc` で transcript 全体（assistant message かつ `usage` を持つエントリ）を走査し、input/output/cache_read/cache_create の累積値・モデル別単価表に基づく推定コスト・cache_ratio を算出する
4. 算出結果と `hook_duration_ms "$HOOK_START_TIME"` の結果を1行にフォーマットし、`logs/token-usage/<YYYY-MM>.log` へ追記する

根拠: `hooks/log-token-usage.sh:1-83`

## 主要な判定ロジック・フロー

- ログは Stop イベントのたびに *累積値* を再計算して1行追記するため、同一セッションについて複数行が存在し、後の行ほど値が大きい（`scripts/analyze_token_usage.py` 側が最終行のみを採用してこれを吸収する）
- `duration_ms` フィールドはこの累積値とは性質が異なり、**その回の Stop hook 呼び出し単体の実行時間**（非累積・per-invocation）である。ログの末尾に `duration_ms=<ms|NA>` として任意フィールドで追加し、旧フォーマットの行（フィールド自体が存在しない）とも後方互換になるようにした
- `REPO_DIR` の解決（`BASH_SOURCE[0]` の symlink 解決）を、従来はログファイルパス算出の直前（スクリプト末尾）でのみ行っていたが、`hooks/lib/hook-timing.sh` を source するために計測開始直後（スクリプト冒頭）へ移動した。ログファイルパスの算出はこの early-resolved `REPO_DIR` を再利用する

根拠: `hooks/log-token-usage.sh:4-13`, `hooks/log-token-usage.sh:73-83`

## 重要な設計判断とその理由

`HOOK_START_TIME` を `payload=$(cat)` より前に取得しているのは、この後に続く `jq -rsc` による transcript 全体の再集計が、transcript が大きいセッションほど処理コストの支配的要因になり得るため、その処理時間を含めて計測する必要があるため。

`hooks/auto-approve-readonly.sh` の `duration_ms` 実装（issue #219）と同じ「後方互換な任意末尾フィールド + `"NA"` フォールバック」パターンを踏襲した。計測ロジック自体は `hooks/lib/hook-timing.sh` に共通化したが、`auto-approve-readonly.sh` 自体は変更していない（詳細は `hooks/lib/hook-timing.sh.md` を参照）。

## 統合ポイント

- 出力先: `logs/token-usage/<YYYY-MM>.log`
- 消費者: `scripts/analyze_token_usage.py`（`commands/analyze-token-usage.md` 経由）
- 依存: `hooks/lib/hook-timing.sh`（`hook_duration_ms` を source して使用）
- 登録: `install.sh` が `hooks/*.sh` を `~/.claude/hooks/` / `~/.codex/hooks/` へ symlink し、Stop イベントとして登録する

## 注意事項・既知の制限

- `set -euo pipefail` の下で動作するため、`hook_duration_ms` 呼び出しやその前段の `source` が失敗すると hook 全体が異常終了する。ただし `hooks/lib/hook-timing.sh` は純粋な bash 演算のみで外部コマンドに依存しないため、通常運用でこの経路が失敗することは想定していない
- `$EPOCHREALTIME` 非対応の bash（5.0未満）では `duration_ms=NA` となり、`scripts/analyze_token_usage.py` 側の集計から除外される

## 変更履歴（git log より自動生成）

- a565c97 feat(#252): add hook execution-time aggregation to /analyze-* commands
- 5b554ea fix: resolve symlink in BASH_SOURCE and move state init to UserPromptSubmit
- 381715b feat(#69): consolidate hook log outputs under logs/ directory
- c8a445c feat(#43): add session name and cost_usd to token log, extend show script with cost analytics
- eda8e56 feat: add model/turns/branch/cwd/cache_ratio to token usage log and show script
- 653dd85 feat(#15): add Stop hook to log token usage per session
