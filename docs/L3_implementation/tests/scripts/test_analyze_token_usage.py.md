# `tests/scripts/test_analyze_token_usage.py` specification

## 目的・役割

`scripts/analyze_token_usage.py` の行パース・累積値の重複排除・集計ロジックを検証する pytest テスト。

根拠: `tests/scripts/test_analyze_token_usage.py:1-13`

## 動作概要

同一セッション `s1` の2行（累積値が増加。`duration_ms` はそれぞれ `10` と `20` で、累積値ではなく行ごとに異なる）、別セッション `s2`（低キャッシュ効率の例。`duration_ms=NA`）、`s3`（高トークン密度の例。`duration_ms` フィールド自体が無い旧フォーマット行）からなる合成ログを使い、以下を検証する:

- `parse_line()` が固定幅パディングを含む行から全フィールドを正しく抽出すること（`duration_ms` を含む）
- `duration_ms` フィールドが存在しない行（`s3` 相当）も後方互換で正しくパースでき、`record["duration_ms"]` が `None` になること
- `dedupe_last_per_session()` が `s1` について**後の行（値が大きい方）のみ**を残すこと（`test_dedupe_keeps_last_row_per_session`）— これが本スクリプトの中核となる正しさの担保
- `aggregate()` の `total_cost_usd` が dedupe 後の値の合計であり、全行単純合算（水増しされた値）と一致しないこと
- `low_cache_sessions`（`turns > 2` かつ `cache_ratio < 50%`）・`high_density_sessions`（`total/turns > 20000`）が正しいセッションのみを抽出すること
- `avg_cache_ratio`（3セッションの cache_ratio 単純平均）、`low_cache_sessions_ratio` / `high_density_sessions_ratio`（該当セッション数 ÷ `session_count`）が正しく算出されること
- `duration_ms_stats` が dedupe **前**の生 `records`（4行）を対象にプールし、`s1` の2行（`10` と `20`）が両方カウントされること（`sample_count=2`・`avg_ms=15.0`）。`s2` の `"NA"` と `s3` のフィールド欠損は合わせて `excluded_count=2` になること。サンプルが1件もない場合（空リスト直接呼び出し）はゼロ値スタッツを返すこと
- `main()` を `sys.argv` 差し替えで直接実行し、標準出力が妥当な JSON であること

根拠: `tests/scripts/test_analyze_token_usage.py:15-100`

## 重要な設計判断

`test_aggregate_uses_deduped_totals` のコメントで「1.0+3.0+9.5+2.5 ではなく 3.0+9.5+2.5」であることを明示し、累積値ログを誤って単純合算する退行を防ぐ回帰テストとして機能させている。

`avg_cache_ratio` / `low_cache_sessions_ratio` / `high_density_sessions_ratio` の期待値は、既存の3セッション固定フィクスチャ（`s1`: cache_ratio 90.0・turns 3、`s2`: cache_ratio 10.0・turns 5、`s3`: cache_ratio 95.0・turns 1）からの手計算値で固定している（issue #216）。

`test_duration_ms_stats_pools_raw_records_not_deduped_sessions` のテスト名とコメントは、`duration_ms_stats` が他の指標と異なり dedupe 後の `sessions` ではなく生の `records` を対象にすることを明示的に固定する回帰テストである。`s1` の1行目（`duration_ms=10`）は dedupe で捨てられる行だが、`duration_ms_stats` の集計には含まれる必要があるため、この2つの集計対象の違いを混同する退行を検出できるようにした（issue #252）。

## 統合ポイント

- 対象: `scripts/analyze_token_usage.py`, `scripts/lib/analyze_common.py`
- 実行: `python3 -m pytest tests/scripts/test_analyze_token_usage.py`
- `tests/scripts/conftest.py` が `scripts/` を `sys.path` に追加している

## 注意事項・既知の制限

月をまたぐセッション（前月末開始・翌月初終了）の重複排除は、複数ログファイルを跨いだケースとしては明示的にテストしていない。

## 変更履歴（git log より自動生成）

- a565c97 feat(#252): add hook execution-time aggregation to /analyze-* commands
- 594905d feat(#216): redesign /analyze-* reports around KPI dashboards and findings
- d7a7627 feat(#212): add /analyze-access, /analyze-auto-approve, /analyze-token-usage log analysis commands
