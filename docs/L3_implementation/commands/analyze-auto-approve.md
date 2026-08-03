# `commands/analyze-auto-approve.md` specification

## 目的・役割

`logs/auto-approve/*.log`（`hooks/auto-approve-readonly.sh` が記録する PreToolUse 判定ログ）を集計し、KPIダッシュボードと、KPIごとの所見・改善提案（Key Findings & Proposals）を提示する read-only workflow。目的は安全性を保ちながら自動承認率を100%に近づけるためのチューニング材料の提供。通常 `/work` から呼ばれる。

根拠: `commands/analyze-auto-approve.md:1-12`

## 動作の概要

5 Step で構成される:

```
Step 0: ARGUMENTS から対象月（YYYY-MM / all / 省略=最新月）を解釈
Step 1: scripts/analyze_auto_approve.py を実行し JSON を取得
Step 2: JSON の値を Primary/Supporting KPI と Evidence（裏付けデータ）に分けて整理
Step 3: KPI・Evidence のみを根拠に Key Findings（主要な発見）+ Proposals（改善提案）+ Risks and Unknowns を執筆
Step 4: logs/reports/auto-approve/<target>_<timestamp>.html を新規作成（KPIダッシュボードを冒頭に、Findings/Proposals をメインコンテンツに、Facts は Evidence として補助的に配置）
Step 5: 標準出力へレポートパスと KPI・上位の発見/提案を提示
```

根拠: `commands/analyze-auto-approve.md:17-84`

## 主要な判定ロジック・フロー

- ログの生データは直接 Read しない。数値の根拠は `scripts/analyze_auto_approve.py` が出力する JSON のみ
- `hooks/auto-approve-readonly.sh` 自体の変更は行わない。改善案は Proposals として提示するに留める
- **Primary KPI** は2つ: 全体の自動承認率 `result_ratio_pct.approved`、および定型処理（`/work` パイプラインの git/gh write系操作）のユーザー確認率 `routine_ops.result_ratio_pct.user_prompt`（目標0%）。後者は issue #216 で追加された、`/work` の実運用に紐づく具体的なチューニング対象
- **Supporting KPI** は `result_ratio_pct.user_prompt` / `result_ratio_pct.blocked`（全体の摩擦・防御指標）、`monthly_trend`（時系列でのチューニング効果測定）、`routine_ops.patterns_needing_approval`（user_prompt に落ちている定型処理パターンの具体的なリスト。恒久的に自動承認へ追加すべき候補をAIが読み取れる形にしたもの）
- Step 3 では `patterns_needing_approval` の上位パターンごとに「なぜ現状 user_prompt に落ちているか」と「恒久的に自動承認へ追加する場合の具体的な提案」をセットで記述する

根拠: `commands/analyze-auto-approve.md:17-27`, `commands/analyze-auto-approve.md:39-53`

## 重要な設計判断とその理由

hook の許可ルールを直接変更すると read-only 分析の境界を越えるため、この command はあくまで観測・提案に限定する。実際の hook 改修は別途 `/work` を経由した通常の task/patch フローで行う。

以前は Facts（統計テーブル）がレポートの主役で、分析は付け足しだった。目的は「自動承認率を安全に100%へ近づける」というチューニングであり、統計はそのためのエビデンスに過ぎないため、KPIダッシュボード → Key Findings & Proposals をメインコンテンツとし、Facts は Evidence として補助セクションに格下げした（issue #216）。

`routine_ops` の分類基準は `hooks/auto-approve-readonly.sh` の `check_session_approved()` をそのままミラーしている（`scripts/analyze_auto_approve.py` 側の設計判断を参照）。独自基準を作ると hook の実挙動とズレるため、唯一の正の情報源をそのまま参照する方針にした。

## 統合ポイント

- 呼び出し元: `commands/work.md`
- 呼び出すもの: `scripts/analyze_auto_approve.py`
- Codex wrapper: `skills/analyze-auto-approve/SKILL.md`
- 出力先: `logs/reports/auto-approve/`（`logs/` は `.gitignore` 対象）
- 分析対象の生成元: `hooks/auto-approve-readonly.sh` の `log_decision()`
- `routine_ops` の分類基準の参照元: `hooks/auto-approve-readonly.sh` の `check_session_approved()`

## 注意事項・既知の制限

- 唯一の書き込みは `logs/reports/auto-approve/` 配下の新規 HTML ファイルのみ
- `detail` フィールドは hook 側で 120 バイトに truncate 済みのため、長いコマンド全文はログに残っていない
- `routine_ops` は hook の allowlist カテゴリの手動ミラーであり自動同期されない。hook の allowlist が変わった場合、`scripts/analyze_auto_approve.py` の `ROUTINE_OP_PATTERNS` も追従して更新する必要がある

## 変更履歴（git log より自動生成）

- d7a7627 feat(#212): add /analyze-access, /analyze-auto-approve, /analyze-token-usage log analysis commands
