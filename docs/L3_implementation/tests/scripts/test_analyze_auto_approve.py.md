# `tests/scripts/test_analyze_auto_approve.py` specification

## 目的・役割

`scripts/analyze_auto_approve.py` の行パース・集計ロジックを検証する pytest テスト。

根拠: `tests/scripts/test_analyze_auto_approve.py:1-11`

## 動作概要

2つの合成ログ定数を使う。

`LOG_CONTENT`（8行、`duration_ms` フィールドなし）: 2026-08: 1セッションに approved 1件・blocked 2件（同一detail）・user_prompt 1件、別セッションに approved 1件、agent は claude/codex 混在、加えて同一セッション内で `git commit` が user_prompt→approved(session) と遷移する2行。2026-09: 別セッションで `git commit` が user_prompt になる1行。

`DURATION_LOG_CONTENT`（6行、`duration_ms_stats` 専用）: `git commit` x3（10/20/30ms）・`git push`（200ms）・`git fetch`（`duration_ms=NA`）・`Read`（`duration_ms` フィールド自体が欠損）。

`TRUNCATION_LOG_CONTENT`（5行、`sample_commands` / `truncated_detail_count` 専用）: `git push origin feature-a`（user_prompt x2、異なるセッション）・`git push origin feature-b`（user_prompt x1）・120文字を超える `git commit` の detail（`LONG_COMMAND_DETAIL`、user_prompt x1）・`git push (session)`（approved x1、`patterns_needing_approval` には出ない件数として利用）。

以下を検証する:

- `parse_line()` が固定幅パディングを含む行から `timestamp`/`agent`/`session`/`result`/`tool`/`detail` を正しく抽出すること
- `detail` が空文字列のケース（`update_plan` など tail 引数なしの `log_decision` 呼び出し）を正しく処理すること
- `monkeypatch` で `repo_root` を差し替えた上で `load_decisions()` → `aggregate()` を通した集計値（`result_counts`・`result_ratio_pct`・`tool_counts`・`agent_counts`・`top_sessions`・`top_blocked_patterns`・`top_user_prompt_patterns`・`recent_blocked_samples`）が期待値と一致すること
- `monthly_trend` が `timestamp` の年月（2026-08 / 2026-09）ごとに正しくグルーピングされ、各月の `total_decisions` / `result_counts` が一致すること
- `routine_ops` が `git commit` 系の Bash コマンドのみを定型処理として分類し、`patterns_needing_approval` に `user_prompt_count` 降順で `git commit`（user_prompt 2件・approved 1件、`sample_commands` に `'git commit -m "later"'` / `'git commit -m "wip"'` を count=1 かつ辞書順で含む）が含まれること。`rm -rf /` や `curl example.com` は定型処理として分類されないこと。`routine_ops.truncated_detail_count` が0であること
- `pattern_command_samples()` が `sample_commands` を `(count 降順, detail 昇順)` で並べること（`TRUNCATION_LOG_CONTENT` の `git push origin feature-a`（count=2）が `git push origin feature-b`（count=1）より先に来る）
- 120文字以上の detail（`LONG_COMMAND_DETAIL`）を持つ `sample_commands` 要素の `possibly_truncated` が `True` になり、`routine_ops.truncated_detail_count` にも反映されること
- `duration_ms_stats` が数値の `duration_ms`（`git commit` x3・`git push` x1）のみを集計対象とし、`"NA"` 1件とフィールド欠損1件を `excluded_count` として除外すること。`avg_ms` / `median_ms` / `p95_ms` / `max_ms` が期待値と一致し、`top_slow_patterns` が `(tool, detail)` 別の `avg_ms` 降順（`git push` → `git commit`）で並ぶこと（別の合成ログ `DURATION_LOG_CONTENT` を使用）
- `duration_ms_stats` は数値 `duration_ms` を1件も含まないログ（`LOG_CONTENT`）に対して `sample_count=0`・数値系フィールドは全て `0.0`・`top_slow_patterns=[]` を返すこと
- `main()` を `sys.argv` 差し替えで直接実行し、標準出力が妥当な JSON であること

根拠: `tests/scripts/test_analyze_auto_approve.py:54-155`, `tests/scripts/test_analyze_auto_approve.py:157-241`

## 重要な設計判断

同一 `(tool, detail)` の blocked 行を2件含めることで、`top_blocked_patterns` のグルーピング（完全一致カウント）を明示的に検証している。

`git commit` を意図的に3パターン（session未承認でuser_prompt→session承認後にapproved→別セッションで再びuser_prompt）含めることで、`routine_ops` が「同じ定型処理パターンでも承認状況はセッション次第で変わる」実際の挙動を再現し、`patterns_needing_approval` が本当に「まだ user_prompt に落ちているものだけ」を拾うことを検証している（issue #216）。

`TRUNCATION_LOG_CONTENT` を専用の合成ログとして分離したのは、`sample_commands` の並び順（頻度→辞書順のタイブレーク）と `possibly_truncated` 判定という2つの新しい振る舞いを、既存の `LOG_CONTENT`（詳細な件数アサーションを既に大量に持つ）に混ぜず独立に検証するため（issue #278）。`LONG_COMMAND_DETAIL` をモジュール定数として定義しているのは、テスト本体でも期待値としてそのまま参照し、120文字という閾値の意味をハードコードした文字列リテラルで重複させないため。

## 統合ポイント

- 対象: `scripts/analyze_auto_approve.py`, `scripts/lib/analyze_common.py`
- 実行: `python3 -m pytest tests/scripts/test_analyze_auto_approve.py`
- `tests/scripts/conftest.py` が `scripts/` を `sys.path` に追加している

## 注意事項・既知の制限

合成ログの `detail` はプレーンな文字列のみ。実際のログに含まれ得る `=` を含むコマンド断片（例: `SESSION_ID="..."`）のような複雑なケースは個別にはテストしていない。`routine_ops` のテストも `git commit` / `git push` の2パターンのみで、`ROUTINE_OP_PATTERNS` の他の分岐（`gh pr merge` 等）は個別にはテストしていない。`sample_commands` が `SAMPLE_COMMANDS_PER_PATTERN`（10件）で切り詰められるケース（ユニークコマンドが11件以上）は個別にはテストしていない。

## 変更履歴（git log より自動生成）

- 13987a8 feat(#219): add duration_ms timing to auto-approve-readonly.sh decision log
- 594905d feat(#216): redesign /analyze-* reports around KPI dashboards and findings
- d7a7627 feat(#212): add /analyze-access, /analyze-auto-approve, /analyze-token-usage log analysis commands
