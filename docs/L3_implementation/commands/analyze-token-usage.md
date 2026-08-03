# `commands/analyze-token-usage.md` specification

## 目的・役割

`logs/token-usage/*.log`（`hooks/log-token-usage.sh` が記録するトークン使用量ログ）を集計し、Facts と AI による分析（Assessment/Opinions/Proposals/Risks）を分離したレポートを提示する read-only workflow。通常 `/work` から呼ばれる。

根拠: `commands/analyze-token-usage.md:1-10`

## 動作の概要

5 Step で構成される:

```
Step 0: ARGUMENTS から対象月（YYYY-MM / all / 省略=最新月）を解釈
Step 1: scripts/analyze_token_usage.py を実行し JSON を取得
Step 2: JSON の値をそのまま Facts として整理（コスト・トークン・モデル別/プロジェクト別内訳・日別推移等）
Step 3: Facts のみを根拠に Assessment/Opinions/Proposals/Risks and Unknowns を執筆
Step 4: logs/reports/token-usage/<target>_<timestamp>.html を新規作成
Step 5: 標準出力へレポートパスと要約を提示
```

根拠: `commands/analyze-token-usage.md:14-72`

## 主要な判定ロジック・フロー

- `logs/token-usage/*.log` はセッションごとに Stop イベントのたびに**その時点までの累積値**が追記される形式である。`scripts/analyze_token_usage.py` がセッションIDごとに最終行のみを集計に用いるため、この command は生ログを直接読まず、スクリプトの重複排除後の JSON のみを根拠とする
- スクリプトの出力には `raw_line_count`（生の行数）と `session_count`（重複排除後）の両方が含まれ、両者を混同しないことを Step 1 で明示する

根拠: `commands/analyze-token-usage.md:16-29`

## 重要な設計判断とその理由

累積値ログをそのまま合算すると同一セッションの値を毎ターン重複計上してしまう（既存の `scripts/show-token-usage.sh --sum` はこの重複排除を行っていない）。この command 系列では正しい月次コストを示すため、セッションIDごとの最終値のみを合算する方式を採用した。

## 統合ポイント

- 呼び出し元: `commands/work.md`
- 呼び出すもの: `scripts/analyze_token_usage.py`
- Codex wrapper: `skills/analyze-token-usage/SKILL.md`
- 出力先: `logs/reports/token-usage/`（`logs/` は `.gitignore` 対象）
- 関連する既存ツール: `scripts/show-token-usage.sh`（集計方式が異なる点に注意）

## 注意事項・既知の制限

- 唯一の書き込みは `logs/reports/token-usage/` 配下の新規 HTML ファイルのみ
- `scripts/show-token-usage.sh` は `~/.claude/token-usage.log`（レガシーパス）を読む一方、`hooks/log-token-usage.sh` の現在の書き込み先は `logs/token-usage/<YYYY-MM>.log` であり、両者は異なるログを参照している

## 変更履歴（git log より自動生成）

- d7a7627 feat(#212): add /analyze-access, /analyze-auto-approve, /analyze-token-usage log analysis commands
