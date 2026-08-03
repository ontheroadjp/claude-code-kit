# `tests/scripts/test_analyze_auto_approve.py` specification

## 目的・役割

`scripts/analyze_auto_approve.py` の行パース・集計ロジックを検証する pytest テスト。

根拠: `tests/scripts/test_analyze_auto_approve.py:1-11`

## 動作概要

5行の合成ログ（1セッションに approved 1件・blocked 2件（同一detail）・user_prompt 1件、別セッションに approved 1件、agent は claude/codex 混在）を使い、以下を検証する:

- `parse_line()` が固定幅パディングを含む行から `timestamp`/`agent`/`session`/`result`/`tool`/`detail` を正しく抽出すること
- `detail` が空文字列のケース（`update_plan` など tail 引数なしの `log_decision` 呼び出し）を正しく処理すること
- `monkeypatch` で `repo_root` を差し替えた上で `load_decisions()` → `aggregate()` を通した集計値（`result_counts`・`result_ratio_pct`・`tool_counts`・`agent_counts`・`top_sessions`・`top_blocked_patterns`・`top_user_prompt_patterns`・`recent_blocked_samples`）が期待値と一致すること
- `main()` を `sys.argv` 差し替えで直接実行し、標準出力が妥当な JSON であること

根拠: `tests/scripts/test_analyze_auto_approve.py:37-70`

## 重要な設計判断

同一 `(tool, detail)` の blocked 行を2件含めることで、`top_blocked_patterns` のグルーピング（完全一致カウント）を明示的に検証している。

## 統合ポイント

- 対象: `scripts/analyze_auto_approve.py`, `scripts/lib/analyze_common.py`
- 実行: `python3 -m pytest tests/scripts/test_analyze_auto_approve.py`
- `tests/scripts/conftest.py` が `scripts/` を `sys.path` に追加している

## 注意事項・既知の制限

合成ログの `detail` はプレーンな文字列のみ。実際のログに含まれ得る `=` を含むコマンド断片（例: `SESSION_ID="..."`）のような複雑なケースは個別にはテストしていない。

## 変更履歴（git log より自動生成）

- d7a7627 feat(#212): add /analyze-access, /analyze-auto-approve, /analyze-token-usage log analysis commands
