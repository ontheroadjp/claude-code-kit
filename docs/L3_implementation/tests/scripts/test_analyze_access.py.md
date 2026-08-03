# `tests/scripts/test_analyze_access.py` specification

## 目的・役割

`scripts/analyze_access.py` のブロック分割・セクションパース・集計ロジックを検証する pytest テスト。

根拠: `tests/scripts/test_analyze_access.py:1-14`

## 動作概要

固定の3セッション分（重複1ファイル・トークン使用量あり・修正あり / 重複なし・トークン使用量なし・修正なし / 重複2ファイル・無駄な再読み込みが多い・修正なし）の合成ログ文字列 `LOG_CONTENT` を使い、以下を検証する:

- `split_blocks()` がブロックを正しく3件に分割すること
- `parse_session()` が総アクセス数・重複ファイル・修正ファイル・トークン使用量を正しく抽出すること
- 重複なし（`重複アクセス: なし`）・トークン使用量セクション欠如のケースを正しく `[]` / `None` として扱うこと
- `monkeypatch` で `lib.analyze_common.repo_root` を `tmp_path` に差し替え、`load_sessions()` → `aggregate()` を通した集計値（セッション数・総アクセス数・上位重複ファイル・`redundant_access_waste`）が期待値と一致すること
- `redundant_accesses_total` / `sessions_with_duplicates` / `sessions_with_duplicates_ratio` が、セッション単位の重複（`count - 1` の合計）から正しく算出されること
- `top_redundant_sessions` が無駄な再読み込み回数の降順（2ファイル重複の SESSION_3 が最上位）で並び、各要素が日時・無駄な再読み込み回数・重複ファイル一覧・`modified`（そのセッションで実際にファイルを修正したか）を保持すること
- `main()` を `sys.argv` 差し替えで直接実行し、標準出力が妥当な JSON であること

根拠: `tests/scripts/test_analyze_access.py:129-179`, `tests/scripts/test_analyze_access.py:181-194`

## 重要な設計判断

`repo_root()` を monkeypatch することで、実ログファイルシステムに触れずに `logs/access/<month>.log` の読み込みパスだけを差し替えている。これにより実行環境（このリポジトリの `logs/`）に依存しない再現可能なテストになっている。

`test_aggregate_across_sessions` は `redundant_access_waste` の期待値（`estimated_wasted_tokens` / `estimated_wasted_cost_usd` / `estimated_waste_ratio_pct`）を、SESSION_1（重複1件・トークン使用量あり）単体の手計算値で固定して回帰を検出する（issue #216）。

## 統合ポイント

- 対象: `scripts/analyze_access.py`, `scripts/lib/analyze_common.py`
- 実行: `python3 -m pytest tests/scripts/test_analyze_access.py`
- `tests/scripts/conftest.py` が `scripts/` を `sys.path` に追加している

## 注意事項・既知の制限

合成ログは実ログのごく一部のパターン（重複1ファイル/なし/2ファイル、トークン使用量あり/なし、修正あり/なし）のみをカバーする。フェーズが複数（`work`/`task`/`patch` 等）に渡るケースは明示的にはテストしていない（本スクリプトはフェーズ別集計自体を持たない）。

## 変更履歴（git log より自動生成）

- 594905d feat(#216): redesign /analyze-* reports around KPI dashboards and findings
- 8d0793a feat(#214): track per-session redundant file reads in /analyze-access
- d7a7627 feat(#212): add /analyze-access, /analyze-auto-approve, /analyze-token-usage log analysis commands
