# `scripts/analyze_auto_approve.py` specification

## 目的・役割

`logs/auto-approve/*.log`（`hooks/auto-approve-readonly.sh` の `log_decision()` が記録する PreToolUse 判定ログ）をパースし、集計結果を JSON として標準出力へ出力する。HTML生成・分析文の作成は行わない（`commands/analyze-auto-approve.md` が担う）。

根拠: `scripts/analyze_auto_approve.py:1-7`

## 動作の概要

1. 1行1判定の形式（`[timestamp] agent=X session=Y result=R tool=T duration_ms=<ms|NA> <detail>`、`result`/`tool` は固定幅パディング済み）を `LINE_RE` でパースする。`duration_ms=...` は任意グループのため、このフィールドが存在しない旧フォーマットのログ行も同じ規則で解析できる
2. `load_decisions(months)` で対象月の全ログファイルを読み、判定のリストを作る
3. `aggregate(months, decisions)` で以下を計算する:
   - `result_counts` / `result_ratio_pct`（approved / blocked / user_prompt の件数と比率）
   - `tool_counts` / `agent_counts`
   - `top_sessions`（判定数上位セッション）
   - `top_blocked_patterns` / `top_user_prompt_patterns`（`(tool, detail)` の完全一致でグルーピングした上位パターン）
   - `recent_blocked_samples` / `recent_user_prompt_samples`（直近 `RECENT_N` 件のサンプル）
   - `monthly_trend`（`timestamp` の年月ごとにグルーピングした判定数・result内訳・比率の時系列）
   - `routine_ops`（`/work` パイプラインの定型処理として分類できた Bash コマンドの内訳）
   - `duration_ms_stats`（`duration_ms` の数値集計。`sample_count` / `excluded_count` / `avg_ms` / `median_ms` / `p95_ms` / `max_ms` / `top_slow_patterns`）
4. `main()` で `lib.analyze_common` の共通CLI・月解決処理を呼び、結果を JSON として出力する

根拠: `scripts/analyze_auto_approve.py:97-347`

## 主要な判定ロジック・フロー

- `count_values()` は TypedDict のキーを文字列引数で動的に取り出す代わりに、呼び出し側で `(d["field"] for d in decisions)` というジェネレータを渡す設計にしている。これにより mypy strict 下で `# type: ignore` を使わずに型安全性を保っている
- `top_detail_patterns()` は完全一致の `(tool, detail)` ペアでグルーピングする。`detail` は hook 側で120バイトに truncate 済みのため、長いコマンドの一部だけが一致してグルーピングされることは想定していない
- `classify_routine_op(tool, detail)` は `ROUTINE_OP_PATTERNS` の正規表現リストを先頭一致で試し、Bash の `detail` 先頭が `hooks/auto-approve-readonly.sh` の `check_session_approved()` が認識する git/gh write系コマンド形状（`git add` / `git commit` / `git push` / ... / `gh pr merge` 等）に一致すればそのラベルを返す。一致しなければ `None`（定型処理として扱わない）。パターンの並び順・粒度は `check_session_approved()` の分岐と1:1対応させており、あるパターンを恒久的に自動承認へ追加したくなった場合、hook 側のどの正規表現分岐を編集すべきかがそのまま分かるようにしている
- `routine_ops_breakdown()` は `classify_routine_op` で分類できた判定のみを対象に、パターンごとの result 内訳を集計し、`user_prompt_count > 0` のパターンを `user_prompt_count` 降順で `patterns_needing_approval` として抽出する。各要素には `pattern_command_samples()` の結果を `sample_commands` として付与し、`routine_ops` 直下には全パターン跨ぎの `truncated_detail_count` を添える（issue #278）
- `pattern_command_samples(routine, label, n)` は該当パターンかつ `result == "user_prompt"` の `detail` を `count_values()` でユニーク集計し、`(count 降順, detail 昇順)` でソートして上位 `n` 件を返す。件数タイ時のソート順を `detail` の辞書順で固定しているのは、テストの期待値を決定論的にするため。各要素は `{"command", "count", "possibly_truncated"}` を持ち、`possibly_truncated` は `len(command) >= DETAIL_TRUNCATE_LIMIT`（120、`hooks/auto-approve-readonly.sh` の `truncate_utf8_safe ... 120` とそろえた値）で判定する。120文字ちょうどの非truncateコマンドを誤って truncated 扱いする可能性があるのは既知の制限（下記）
- `monthly_trend()` は `timestamp` の先頭 `MONTH_PATTERN_LENGTH`（7文字 = `YYYY-MM`）を月キーとして `decisions` をグルーピングする
- `numeric_duration_ms(decision)` は `duration_ms` が数字のみ（`str.isdigit()`）の場合にのみ `int` を返し、`None` および `"NA"` は `None` として扱う（例外送出ではなく判定で除外する設計）
- `duration_ms_stats(decisions, n)` は `numeric_duration_ms` で数値化できた `duration_ms` のみを対象に `avg_ms` / `median_ms`（`statistics.median`）/ `p95_ms`（`lib.analyze_common.percentile()`、`statistics.quantiles(..., method="inclusive")`）/ `max_ms` を計算し、`top_slow_patterns(decisions, n)`（`(tool, detail)` 別の平均処理時間 `avg_ms` 降順 TOP `n`、`top_blocked_patterns` と同じグルーピング様式）を添える。数値サンプルが1件のみの場合は `percentile()` がそのまま単一値を返す（`statistics.quantiles` は2件未満で例外を送出するため）。数値サンプルが0件の場合は `sample_count=0`・数値系フィールドは全て `0.0`・`top_slow_patterns=[]` を返す（`ratio()` が `total=0` を `0.0` で扱う既存の設計と揃えている）

根拠: `scripts/analyze_auto_approve.py:124-238`, `scripts/analyze_auto_approve.py:241-301`

## 重要な設計判断とその理由

`result_ratio_pct` の `user_prompt` 比率を摩擦指標として扱う設計は、hook 自体（`hooks/auto-approve-readonly.sh`）の許可ルールがどれだけカバレッジを持っているかを定量的に示すため。`blocked` は防御が機能した件数であり、`user_prompt` は自動判定できず人間の確認に落ちた件数という区別を JSON レベルで保持している。

`/analyze-auto-approve` の目的は「安全性を保ちながら自動承認率を100%に近づける」ことであり、その一部として「`/work` パイプラインの定型処理（git/gh write系操作）がどれだけユーザー確認に落ちているか」を明示的な KPI として求められた（issue #216）。これを実データから機械的に判定するために、`hooks/auto-approve-readonly.sh` が既に持つ `check_session_approved()` の分類ロジックをそのまま踏襲した。独自の分類基準を新しく作ると hook の実際の動作とズレるおそれがあるため、既存の唯一の正の情報源（hook 自体の allowlist）をミラーする設計にした。ただし文字列一致の複製であるため、hook 側の allowlist が変わった場合はこのファイルの `ROUTINE_OP_PATTERNS` も追従して更新する必要がある（ドリフトの可能性は `docs/L3_implementation/commands/analyze-auto-approve.md` にも明記）。

`monthly_trend` は、`--all` 実行時に過去のチューニング施策（hook の allowlist 拡張など）が自動承認率を実際に改善させたかどうかを時系列で確認できるようにするために追加した。

`duration_ms_stats` は「hook 自体の実行時間が体感レイテンシに寄与しているか」を数値で判断できるようにするために追加した（issue #218）。集計手段として標準ライブラリ `statistics` を採用し、独自の百分位計算ロジックは実装していない — 統計ロジックの正しさを自前で検証・保守するコストを避けるため。`"NA"` は bash < 5.0 で `$EPOCHREALTIME` が使えず計測できなかったことを表す欠損値であり、0 として扱うと平均値が不当に下がるため `excluded_count` として分離し数値集計から完全に除外する設計にした。

`percentile()` はもともとこのファイルの内部関数だったが、`scripts/analyze_access.py` / `scripts/analyze_token_usage.py` にも同一の hook 処理時間集計（`duration_ms_stats`）を追加した際、ロジックを複製せず `scripts/lib/analyze_common.py` へ移した（issue #252）。挙動・シグネチャは変更していない。

`patterns_needing_approval` はカテゴリ集計（パターン名＋件数）のみを提供しており、「具体的にどのコマンド文字列を allowlist に足すべきか」の判断にはユーザーが `logs/auto-approve/*.log` の生ログを手動でコピペして精査する必要があった。`sample_commands` はこの手動精査を減らすために追加した（issue #278）。独自の要約・推測は行わず、ログに実際に記録された `detail` 文字列をそのまま頻度付きで返す設計にしている — allowlist 追加の判断材料は AI の解釈ではなく実データそのものであるべきという方針のため。

## 統合ポイント

- 入力: `logs/auto-approve/<YYYY-MM>.log`（`hooks/auto-approve-readonly.sh` が生成）
- 分類ロジックの参照元: `hooks/auto-approve-readonly.sh` の `check_session_approved()`（`tool:git_write` / `tool:gh_issue_write` / `tool:gh_pr_write`）
- 共通処理: `scripts/lib/analyze_common.py`（`MONTH_PATTERN_LENGTH` を月グルーピングに再利用、`percentile()` を `duration_ms_stats` の p95 計算に再利用）
- 呼び出し元: `commands/analyze-auto-approve.md`
- テスト: `tests/scripts/test_analyze_auto_approve.py`

## 注意事項・既知の制限

- `top_blocked_patterns` / `top_user_prompt_patterns` / `top_sessions` は `TOP_N`（10件）、サンプルは `RECENT_N`（15件）に切り詰められる。`routine_ops.patterns_needing_approval` も `TOP_N`（10件）に切り詰められる
- `routine_ops` は Bash ツールの決定のみを対象とする（`classify_routine_op` は `tool != "Bash"` を即座に除外する）
- `ROUTINE_OP_PATTERNS` は `hooks/auto-approve-readonly.sh` の `check_session_approved()` の手動ミラーであり、自動同期はされない。hook 側の allowlist が変わった場合、このファイルも合わせて更新しないと `routine_ops` の分類が古くなる
- `duration_ms_stats.top_slow_patterns` も `TOP_N`（10件）に切り詰められる
- `duration_ms_stats` は `"NA"` およびフィールド欠損（旧フォーマットのログ行）を区別せず一律 `excluded_count` にまとめる。bash バージョンによる計測不能とログフォーマット移行前の欠損を JSON レベルでは区別できない
- `sample_commands` の `possibly_truncated` は `len(command) >= DETAIL_TRUNCATE_LIMIT`（120）による長さのみの判定であり、たまたま120文字ちょうどで終わる非truncateコマンドを誤って truncated 扱いする可能性がある（偽陽性はあるが偽陰性は起きない設計）
- `DETAIL_TRUNCATE_LIMIT`（120）は `hooks/auto-approve-readonly.sh` の `truncate_utf8_safe ... 120` の手動ミラーであり自動同期されない。hook 側の truncate 上限が変わった場合、この定数も追従して更新する必要がある
- `patterns_needing_approval` の各 `sample_commands` は `SAMPLE_COMMANDS_PER_PATTERN`（10件）に切り詰められる。あるパターンのユニークコマンドが10件を超える場合、頻度の低いコマンドは出力に含まれない

## 変更履歴（git log より自動生成）

- a565c97 feat(#252): add hook execution-time aggregation to /analyze-* commands
- ac0a68a feat(#218): add duration_ms aggregation and reporting to /analyze-auto-approve
- 13987a8 feat(#219): add duration_ms timing to auto-approve-readonly.sh decision log
- 594905d feat(#216): redesign /analyze-* reports around KPI dashboards and findings
- d7a7627 feat(#212): add /analyze-access, /analyze-auto-approve, /analyze-token-usage log analysis commands
