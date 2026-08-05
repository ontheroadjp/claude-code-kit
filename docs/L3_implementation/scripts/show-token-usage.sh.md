# scripts/show-token-usage.sh specification

## 目的・役割

`~/.claude/token-usage.log`（`hooks/log-token-usage.sh` が Stop hook で追記）を集計し、複数の表示モード（list / sum / model / cost / project / time / anomaly）で可視化する CLI。

根拠: `scripts/show-token-usage.sh:1-27`, `docs/L3_implementation/scripts/README.md:10`

## 動作の概要

1. `-n <count>` / `-a,--all` / `--sum` / `--model` / `--cost` / `--project` / `--time` / `--anomaly` / `-h,--help` を解析する（デフォルトは list モード、直近20件）
2. モードごとに専用の AWK スクリプト（`PARSE_AWK` / `SUM_AWK` / `MODEL_AWK` / `COST_AWK` / `PROJECT_AWK` / `TIME_AWK` / `ANOMALY_LOW_AWK` / `ANOMALY_DENSE_AWK`）をログに適用し、集計結果を整形して出力する
3. 区切り線は `printf '%Ns' | tr ' ' '─'` という printf の zero-arg padding イディオムで生成する

根拠: `scripts/show-token-usage.sh:44-391`

## 統合ポイント

- データソース: `hooks/log-token-usage.sh`（Stop hook）が生成する `~/.claude/token-usage.log`
- 呼び出し元: `docs/.ai/repo.profile.json` の `commands.analyze:token-usage` とは別系統（`scripts/analyze_token_usage.py` が Python 側の集計、本スクリプトは手動 CLI 表示用）

## 注意事項・既知の制限

- 各モードの AWK スクリプトは変数（`PARSE_AWK` 等）に単一引用符で代入している。AWK 側のフィールド参照 (`$1` 等) をシェルに展開させないための意図的な書き方であり、ShellCheck SC2016 の誤検知対象のためファイル先頭（`set -euo pipefail` の前）に file-wide directive で抑制している
- `printf '%115s' | tr ' ' '─'`（引数なしで `%Ns` を評価し、空文字列を N 文字にパディングして罫線を作る）は ShellCheck SC2183 の誤検知対象のため同様に抑制している
