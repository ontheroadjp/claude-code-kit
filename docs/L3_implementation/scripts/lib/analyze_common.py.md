# `scripts/lib/analyze_common.py` specification

## 目的・役割

`scripts/analyze_access.py` / `analyze_auto_approve.py` / `analyze_token_usage.py` の3スクリプトが共有する、対象月解決・ログファイル列挙・CLI引数定義・JSON出力の共通処理。

根拠: `scripts/lib/analyze_common.py:1`

## 動作の概要

- `repo_root()`: このファイルの位置からリポジトリルートを解決する（`scripts/lib/` の2階層上）
- `log_dir(log_type)` / `available_months(log_type)`: `logs/<log_type>/*.log` を列挙し、`YYYY-MM` 形式のファイル名（stem）を昇順で返す
- `build_arg_parser(description)`: `--month YYYY-MM` と `--all` を相互排他オプションとして持つ `argparse.ArgumentParser` を生成する
- `resolve_target_months(log_type, month, use_all)`: 3つの分岐（`--all` / `--month` 指定 / 省略）で対象月のリストを確定する。省略時は `available_months()` の最後の要素（最新月）を採用する。ログが1件も無い場合や不正な `--month` 値の場合は `SystemExit` でエラーメッセージを出し終了する
- `log_files_for_months(log_type, months)`: 対象月リストから実際のログファイルパスのリストを組み立てる
- `emit_json(data)`: JSON を `indent=2`・`ensure_ascii=False` で標準出力へ書き出す
- `percentile(sorted_values, pct)`: `statistics.quantiles(..., method="inclusive")` で百分位を計算する。ソート済みリストが1件のみの場合はその単一値をそのまま返す（`statistics.quantiles` は2件未満で例外を送出するため）

根拠: `scripts/lib/analyze_common.py:14-75`

## 重要な設計判断とその理由

3スクリプトすべてで「対象月の解決」「JSON出力」のロジックが同一だったため、DRY原則に従い共通モジュールへ抽出した。`resolve_target_months` は個々のログ種別に依存しない汎用実装とし、`log_type` を文字列引数として受け取ることで `access` / `auto-approve` / `token-usage` の3種別に対して同一コードを再利用する。

エラー時に例外を握り潰さず `SystemExit` で即座に終了するのは、コマンド呼び出し元（`commands/analyze-*.md`）がスクリプトの終了コードでエラーを検知し、そのままユーザーへ報告する設計と対応している。

`percentile()` はもともと `scripts/analyze_auto_approve.py` の内部関数だった（issue #218）。`scripts/analyze_access.py` / `scripts/analyze_token_usage.py` にも hook 処理時間の `duration_ms_stats` を追加した際、3スクリプト共通で使う唯一の統計計算だったためここへ移した（issue #252）。挙動・シグネチャは変更していない。

## 統合ポイント

- 呼び出し元: `scripts/analyze_access.py`, `scripts/analyze_auto_approve.py`, `scripts/analyze_token_usage.py`
- 対象データ: `logs/access/`, `logs/auto-approve/`, `logs/token-usage/`

## 注意事項・既知の制限

- 型アノテーションは `commands/coding-py.md` の規約に従い全関数に付与している
- `MONTH_PATTERN_LENGTH` は `"YYYY-MM"` の長さ（7）を表す名前付き定数であり、マジックナンバーを避けている

## 変更履歴（git log より自動生成）

- a565c97 feat(#252): add hook execution-time aggregation to /analyze-* commands
- d7a7627 feat(#212): add /analyze-access, /analyze-auto-approve, /analyze-token-usage log analysis commands
