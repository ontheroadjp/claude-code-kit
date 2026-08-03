# `scripts/analyze_auto_approve.py` specification

## 目的・役割

`logs/auto-approve/*.log`（`hooks/auto-approve-readonly.sh` の `log_decision()` が記録する PreToolUse 判定ログ）をパースし、集計結果を JSON として標準出力へ出力する。HTML生成・分析文の作成は行わない（`commands/analyze-auto-approve.md` が担う）。

根拠: `scripts/analyze_auto_approve.py:1-6`

## 動作の概要

1. 1行1判定の形式（`[timestamp] agent=X session=Y result=R tool=T <detail>`、`result`/`tool` は固定幅パディング済み）を `LINE_RE` でパースする
2. `load_decisions(months)` で対象月の全ログファイルを読み、判定のリストを作る
3. `aggregate(months, decisions)` で以下を計算する:
   - `result_counts` / `result_ratio_pct`（approved / blocked / user_prompt の件数と比率）
   - `tool_counts` / `agent_counts`
   - `top_sessions`（判定数上位セッション）
   - `top_blocked_patterns` / `top_user_prompt_patterns`（`(tool, detail)` の完全一致でグルーピングした上位パターン）
   - `recent_blocked_samples` / `recent_user_prompt_samples`（直近 `RECENT_N` 件のサンプル）
4. `main()` で `lib.analyze_common` の共通CLI・月解決処理を呼び、結果を JSON として出力する

根拠: `scripts/analyze_auto_approve.py:35-146`

## 主要な判定ロジック・フロー

- `count_values()` は TypedDict のキーを文字列引数で動的に取り出す代わりに、呼び出し側で `(d["field"] for d in decisions)` というジェネレータを渡す設計にしている。これにより mypy strict 下で `# type: ignore` を使わずに型安全性を保っている
- `top_detail_patterns()` は完全一致の `(tool, detail)` ペアでグルーピングする。`detail` は hook 側で120バイトに truncate 済みのため、長いコマンドの一部だけが一致してグルーピングされることは想定していない

根拠: `scripts/analyze_auto_approve.py:78-108`

## 重要な設計判断とその理由

`result_ratio_pct` の `user_prompt` 比率を摩擦指標として扱う設計は、hook 自体（`hooks/auto-approve-readonly.sh`）の許可ルールがどれだけカバレッジを持っているかを定量的に示すため。`blocked` は防御が機能した件数であり、`user_prompt` は自動判定できず人間の確認に落ちた件数という区別を JSON レベルで保持している。

## 統合ポイント

- 入力: `logs/auto-approve/<YYYY-MM>.log`（`hooks/auto-approve-readonly.sh` が生成）
- 共通処理: `scripts/lib/analyze_common.py`
- 呼び出し元: `commands/analyze-auto-approve.md`
- テスト: `tests/scripts/test_analyze_auto_approve.py`

## 注意事項・既知の制限

- `top_blocked_patterns` / `top_user_prompt_patterns` / `top_sessions` は `TOP_N`（10件）、サンプルは `RECENT_N`（15件）に切り詰められる
