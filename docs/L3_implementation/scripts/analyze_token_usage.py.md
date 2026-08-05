# `scripts/analyze_token_usage.py` specification

## 目的・役割

`logs/token-usage/*.log`（`hooks/log-token-usage.sh` が記録するトークン使用量ログ）をパースし、集計結果を JSON として標準出力へ出力する。HTML生成・分析文の作成は行わない（`commands/analyze-token-usage.md` が担う）。

根拠: `scripts/analyze_token_usage.py:1-9`

## 動作の概要

1. 1行1ターンの `key=value` 形式（固定幅パディングあり）を `LINE_RE` でパースし `Record` を作る。末尾の `duration_ms=<ms|NA>` は任意グループのため、この機能追加前の行（フィールド自体が無い）も引き続きパースできる
2. `load_records(months)` で対象月の全行を読み込む
3. `dedupe_last_per_session(records)` で **同一 `session` の最後の行のみ**を残す（重要: 詳細は下記）
4. `aggregate(months, records)` は内部で dedupe した上で、`avg_cache_ratio`（セッション横断の cache_ratio 平均）、`model_breakdown` / `cwd_breakdown` / `daily_cost_trend` / `top_expensive_sessions` / `low_cache_sessions` / `high_density_sessions`、`low_cache_sessions_ratio` / `high_density_sessions_ratio`（それぞれの該当セッション数 ÷ `session_count`）、および `duration_ms_stats(records)`（**dedupe 前の生 `records` を使う**。詳細は下記）を計算する
5. `main()` で `lib.analyze_common` の共通CLI・月解決処理を呼び、結果を JSON として出力する

根拠: `scripts/analyze_token_usage.py:90-231`

## 主要な判定ロジック・フロー

`hooks/log-token-usage.sh` は Stop イベントのたびに **transcript 全体を再集計**して1行追記するため、同一セッションについて複数行が存在し、後の行ほど値が大きい（累積）。単純に全行を合算すると同一セッションのコストを何倍にも水増ししてしまうため、`dedupe_last_per_session()` で `session_id` をキーに最後の行だけを残してから集計する。

`raw_line_count`（生の行数）と `session_count`（重複排除後）を両方 JSON に含め、呼び出し元がどちらを見ているか誤認しないようにしている。

`low_cache_sessions`（`turns > 2` かつ `cache_ratio < 50%`）と `high_density_sessions`（`total / turns > 20000`）の閾値は、既存の `scripts/show-token-usage.sh --anomaly` の閾値をそのまま踏襲した。`avg_cache_ratio` / `low_cache_sessions_ratio` / `high_density_sessions_ratio` は、`/analyze-token-usage` の KPI ダッシュボードが冒頭で示す単一の効率指標として issue #216 で追加した（それまでは絶対件数・絶対リストしかなく、レポート冒頭に置ける比率指標が無かった）。

`duration_ms`（`hooks/log-token-usage.sh` 自体の実行時間）はコスト・トークンと違い**累積値ではない** — 各行はその回の Stop hook 呼び出し単体の実行時間を表す。そのため `duration_ms_stats()` は他の指標のように `dedupe_last_per_session()` 後の `sessions`（セッションあたり1行に潰したもの）ではなく、dedupe 前の生 `records`（全行）を対象にプールする。仮に dedupe 後の値を使うと、同一セッション内の2回目以降のターンの `duration_ms` がすべて捨てられてしまう（issue #252）。

根拠: `scripts/analyze_token_usage.py:102-107`, `scripts/analyze_token_usage.py:26-30`, `scripts/analyze_token_usage.py:204-232`

## 重要な設計判断とその理由

累積値ログという性質上、集計ロジックの正しさ（重複排除の有無）がコスト集計の正確性を直接左右する。`tests/scripts/test_analyze_token_usage.py` はこの重複排除を明示的にテストしている。

## 統合ポイント

- 入力: `logs/token-usage/<YYYY-MM>.log`（`hooks/log-token-usage.sh` が生成）
- 共通処理: `scripts/lib/analyze_common.py`（`percentile()` を含む）
- 呼び出し元: `commands/analyze-token-usage.md`
- テスト: `tests/scripts/test_analyze_token_usage.py`
- 関連する既存ツール: `scripts/show-token-usage.sh`（重複排除を行わない別実装。参照パスも `~/.claude/token-usage.log` と異なる）

## 注意事項・既知の制限

- `--all` で複数月を跨ぐ場合、同一セッションが月をまたいで存在する（セッション開始が前月末、終了が翌月初）ケースでは、ファイル読み込み順（月の昇順）が時系列と一致する前提で最後の行を採用している
- `model_breakdown` / `cwd_breakdown` / `top_expensive_sessions` は `TOP_N`（10件、`cwd_breakdown`・`top_expensive_sessions` のみ）に切り詰められる
- `duration_ms_stats` はこの機能追加前に書かれた行（`duration_ms` フィールド自体が無い）を `excluded_count` に含めて数値集計から除外する。全行が旧フォーマットの場合は `sample_count: 0` のゼロ値スタッツを返す

## 変更履歴（git log より自動生成）

- 594905d feat(#216): redesign /analyze-* reports around KPI dashboards and findings
- d7a7627 feat(#212): add /analyze-access, /analyze-auto-approve, /analyze-token-usage log analysis commands
