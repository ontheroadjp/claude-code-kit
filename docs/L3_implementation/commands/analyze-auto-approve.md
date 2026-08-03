# `commands/analyze-auto-approve.md` specification

## 目的・役割

`logs/auto-approve/*.log`（`hooks/auto-approve-readonly.sh` が記録する PreToolUse 判定ログ）を集計し、Facts と AI による分析（Assessment/Opinions/Proposals/Risks）を分離したレポートを提示する read-only workflow。通常 `/work` から呼ばれる。

根拠: `commands/analyze-auto-approve.md:1-11`

## 動作の概要

5 Step で構成される:

```
Step 0: ARGUMENTS から対象月（YYYY-MM / all / 省略=最新月）を解釈
Step 1: scripts/analyze_auto_approve.py を実行し JSON を取得
Step 2: JSON の値をそのまま Facts として整理（result別・tool別・agent別内訳、上位パターン等）
Step 3: Facts のみを根拠に Assessment/Opinions/Proposals/Risks and Unknowns を執筆
Step 4: logs/reports/auto-approve/<target>_<timestamp>.html を新規作成
Step 5: 標準出力へレポートパスと要約を提示
```

根拠: `commands/analyze-auto-approve.md:14-74`

## 主要な判定ロジック・フロー

- ログの生データは直接 Read しない。数値の根拠は `scripts/analyze_auto_approve.py` が出力する JSON のみ
- `user_prompt` 比率（自動承認できず手動確認に落ちた割合）を摩擦指標として Assessment の中心に置く
- `hooks/auto-approve-readonly.sh` 自体の変更は行わない。改善案は Proposals として提示するに留める

根拠: `commands/analyze-auto-approve.md:16-25`, `commands/analyze-auto-approve.md:36-42`

## 重要な設計判断とその理由

hook の許可ルールを直接変更すると read-only 分析の境界を越えるため、この command はあくまで観測・提案に限定する。実際の hook 改修は別途 `/work` を経由した通常の task/patch フローで行う。

## 統合ポイント

- 呼び出し元: `commands/work.md`
- 呼び出すもの: `scripts/analyze_auto_approve.py`
- Codex wrapper: `skills/analyze-auto-approve/SKILL.md`
- 出力先: `logs/reports/auto-approve/`（`logs/` は `.gitignore` 対象）
- 分析対象の生成元: `hooks/auto-approve-readonly.sh` の `log_decision()`

## 注意事項・既知の制限

- 唯一の書き込みは `logs/reports/auto-approve/` 配下の新規 HTML ファイルのみ
- `detail` フィールドは hook 側で 120 バイトに truncate 済みのため、長いコマンド全文はログに残っていない

## 変更履歴（git log より自動生成）

- d7a7627 feat(#212): add /analyze-access, /analyze-auto-approve, /analyze-token-usage log analysis commands
