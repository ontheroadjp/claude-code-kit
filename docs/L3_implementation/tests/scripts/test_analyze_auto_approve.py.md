# `tests/scripts/test_analyze_auto_approve.py` specification

## 目的・役割

`scripts/analyze_auto_approve.py` の行パース・集計ロジックを検証する pytest テスト。

根拠: `tests/scripts/test_analyze_auto_approve.py:1-11`

## 動作概要

8行の合成ログ（2026-08: 1セッションに approved 1件・blocked 2件（同一detail）・user_prompt 1件、別セッションに approved 1件、agent は claude/codex 混在、加えて同一セッション内で `git commit` が user_prompt→approved(session) と遷移する2行。2026-09: 別セッションで `git commit` が user_prompt になる1行）を使い、以下を検証する:

- `parse_line()` が固定幅パディングを含む行から `timestamp`/`agent`/`session`/`result`/`tool`/`detail` を正しく抽出すること
- `detail` が空文字列のケース（`update_plan` など tail 引数なしの `log_decision` 呼び出し）を正しく処理すること
- `monkeypatch` で `repo_root` を差し替えた上で `load_decisions()` → `aggregate()` を通した集計値（`result_counts`・`result_ratio_pct`・`tool_counts`・`agent_counts`・`top_sessions`・`top_blocked_patterns`・`top_user_prompt_patterns`・`recent_blocked_samples`）が期待値と一致すること
- `monthly_trend` が `timestamp` の年月（2026-08 / 2026-09）ごとに正しくグルーピングされ、各月の `total_decisions` / `result_counts` が一致すること
- `routine_ops` が `git commit` 系の Bash コマンドのみを定型処理として分類し、`patterns_needing_approval` に `user_prompt_count` 降順で `git commit`（user_prompt 2件・approved 1件）が含まれること。`rm -rf /` や `curl example.com` は定型処理として分類されないこと
- `main()` を `sys.argv` 差し替えで直接実行し、標準出力が妥当な JSON であること

根拠: `tests/scripts/test_analyze_auto_approve.py:51-113`

## 重要な設計判断

同一 `(tool, detail)` の blocked 行を2件含めることで、`top_blocked_patterns` のグルーピング（完全一致カウント）を明示的に検証している。

`git commit` を意図的に3パターン（session未承認でuser_prompt→session承認後にapproved→別セッションで再びuser_prompt）含めることで、`routine_ops` が「同じ定型処理パターンでも承認状況はセッション次第で変わる」実際の挙動を再現し、`patterns_needing_approval` が本当に「まだ user_prompt に落ちているものだけ」を拾うことを検証している（issue #216）。

## 統合ポイント

- 対象: `scripts/analyze_auto_approve.py`, `scripts/lib/analyze_common.py`
- 実行: `python3 -m pytest tests/scripts/test_analyze_auto_approve.py`
- `tests/scripts/conftest.py` が `scripts/` を `sys.path` に追加している

## 注意事項・既知の制限

合成ログの `detail` はプレーンな文字列のみ。実際のログに含まれ得る `=` を含むコマンド断片（例: `SESSION_ID="..."`）のような複雑なケースは個別にはテストしていない。`routine_ops` のテストも `git commit` 1パターンのみで、`ROUTINE_OP_PATTERNS` の他の分岐（`gh pr merge` 等）は個別にはテストしていない。

## 変更履歴（git log より自動生成）

- 594905d feat(#216): redesign /analyze-* reports around KPI dashboards and findings
- d7a7627 feat(#212): add /analyze-access, /analyze-auto-approve, /analyze-token-usage log analysis commands
