# `tests/scripts/test_analyze_access.py` specification

## 目的・役割

`scripts/analyze_access.py` のブロック分割・セクションパース・集計ロジックを検証する pytest テスト。

根拠: `tests/scripts/test_analyze_access.py:1-9`

## 動作概要

固定の4セッション分（重複1ファイル・単一 phase・トークン使用量あり・修正あり / 重複なし・トークン使用量なし・修正なし / 重複2ファイル・単一 phase・無駄な再読み込みが多い・`[Hook処理時間]` セクションあり・修正なし / 重複1ファイルが2つの phase にまたがる・修正なし）の合成ログ文字列 `LOG_CONTENT` を使い、以下を検証する:

- `split_blocks()` がブロックを正しく4件に分割すること
- `parse_session()` が総アクセス数・重複ファイル（`by_phase` 内訳込み）・修正ファイル・トークン使用量を正しく抽出すること
- `parse_phase_breakdown()` が `"work:2, task:1"` のような複数 phase の内訳を dict に変換すること、およびサフィックスが空文字の場合に `{}` を返すこと
- `parse_summary()` が `[phase:count, ...]` サフィックスを持たない旧フォーマットの重複行（issue #308 以前）を `by_phase == {}` として後方互換にパースすること
- 重複なし（`重複アクセス: なし`）・トークン使用量セクション欠如・`[Hook処理時間]` セクション欠如のケース（SESSION_1・SESSION_2 は `[Hook処理時間]` を持たない旧フォーマット相当）を正しく `[]` / `None` として扱うこと
- SESSION_3 の `[Hook処理時間]`（`45,120,NA`）が `parse_hook_durations()` によりトークンのまま `["45", "120", "NA"]` として抽出されること
- `monkeypatch` で `lib.analyze_common.repo_root` を `tmp_path` に差し替え、`load_sessions()` → `aggregate()` を通した集計値（セッション数・総アクセス数・上位重複ファイル とその `by_phase` 内訳・`redundant_access_waste`）が期待値と一致すること。SESSION_4（`hooks/auto-approve-readonly.sh` が `work`/`task` の2 phase にまたがって重複）により、`top_duplicate_files` の `by_phase` がセッション横断で正しく合算されることを検証する
- `redundant_accesses_total` / `sessions_with_duplicates` / `sessions_with_duplicates_ratio` が、セッション単位の重複（`count - 1` の合計）から正しく算出されること
- `top_redundant_sessions` が無駄な再読み込み回数の降順（SESSION_3, SESSION_4, SESSION_1 の順）で並び、各要素が日時・無駄な再読み込み回数・`by_phase` を含む重複ファイル一覧・`modified`（そのセッションで実際にファイルを修正したか）を保持すること
- `duration_ms_stats` が全セッションの `hook_durations_ms` をプールし（SESSION_3 のみ持つ `45,120,NA` から `"NA"` を除外）、`sample_count=2`・`excluded_count=1`・`avg_ms=82.5`・`max_ms=120` になること。サンプルが1件もない場合（空リスト直接呼び出し）はゼロ値スタッツを返すこと
- `main()` を `sys.argv` 差し替えで直接実行し、標準出力が妥当な JSON であること

根拠: `tests/scripts/test_analyze_access.py:11-125`, `tests/scripts/test_analyze_access.py:182-241`

## 重要な設計判断

`repo_root()` を monkeypatch することで、実ログファイルシステムに触れずに `logs/access/<month>.log` の読み込みパスだけを差し替えている。これにより実行環境（このリポジトリの `logs/`）に依存しない再現可能なテストになっている。

`test_aggregate_across_sessions` は `redundant_access_waste` の期待値（`estimated_wasted_tokens` / `estimated_wasted_cost_usd` / `estimated_waste_ratio_pct`）を、SESSION_1（重複1件・トークン使用量あり）単体の手計算値で固定して回帰を検出する（issue #216）。SESSION_4 は `token_usage` セクションを持たないため、この期待値には影響しない。

`duration_ms_stats` のテストは `"NA"` を意図的に SESSION_3 のフィクスチャへ混在させ、除外ロジック（`excluded_count`）が数値集計に紛れ込まないことを固定する。SESSION_1・SESSION_2 に `[Hook処理時間]` を含めていないのは、この機能追加前に flush されたセッション（後方互換ケース）を自然にカバーするため（issue #252）。

SESSION_4（issue #308）は既存の3セッションとは別に追加した、`hooks/auto-approve-readonly.sh` を `work` phase で2回・`task` phase で1回読んだケースである。SESSION_1/SESSION_3 の重複行は phase タグ（`[work:N]`）を持つ現行フォーマットに更新した一方、`by_phase` が空 dict になる旧フォーマット（サフィックスなし）の後方互換は `test_parse_summary_backward_compatible_with_pre_308_format` で `LOG_CONTENT` を介さず直接 `parse_summary()` に短いテキストを渡して独立に検証している — 全セッションフィクスチャを敢えて新フォーマットへ揃えることで、有効なログが実運用でどう見えるかをテストしつつ、後方互換は単体テストとして別軸に切り分ける設計にした。

## 統合ポイント

- 対象: `scripts/analyze_access.py`, `scripts/lib/analyze_common.py`
- 実行: `python3 -m pytest tests/scripts/test_analyze_access.py`
- `tests/scripts/conftest.py` が `scripts/` を `sys.path` に追加している

## 注意事項・既知の制限

合成ログは実ログのごく一部のパターン（重複1ファイル/なし/2ファイル/2ファイル中1つが2phaseにまたがる、トークン使用量あり/なし、修正あり/なし）のみをカバーする。3 phase 以上にまたがる重複や `patch`/`docs-sync`/`init-docs` phase を含むケースは明示的にはテストしていない（`parse_phase_breakdown()` の正規表現はカンマ区切りの任意個数の `phase:count` を扱えるため、原理上は動作する想定だが、フィクスチャとしては用意していない）。

## 変更履歴（git log より自動生成）

- d2cd65b feat(#308): add phase-tagged duplicate access breakdown to /analyze-access
- a565c97 feat(#252): add hook execution-time aggregation to /analyze-* commands
- 594905d feat(#216): redesign /analyze-* reports around KPI dashboards and findings
- 8d0793a feat(#214): track per-session redundant file reads in /analyze-access
- d7a7627 feat(#212): add /analyze-access, /analyze-auto-approve, /analyze-token-usage log analysis commands
