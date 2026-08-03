# `commands/analyze-access.md` specification

## 目的・役割

`logs/access/*.log`（`hooks/log-access-stop.sh` が記録するアクセスログ）を集計し、Facts と AI による分析（Assessment/Opinions/Proposals/Risks）を分離したレポートを提示する read-only workflow。通常 `/work` から呼ばれる。

根拠: `commands/analyze-access.md:1-10`

## 動作の概要

5 Step で構成される:

```
Step 0: ARGUMENTS から対象月（YYYY-MM / all / 省略=最新月）を解釈
Step 1: scripts/analyze_access.py を実行し JSON を取得
Step 2: JSON の値をそのまま Facts として整理
Step 3: Facts のみを根拠に Assessment/Opinions/Proposals/Risks and Unknowns を執筆
Step 4: logs/reports/access/<target>_<timestamp>.html を新規作成
Step 5: 標準出力へレポートパスと要約を提示
```

根拠: `commands/analyze-access.md:14-73`

## 主要な判定ロジック・フロー

- ログの生データ（数千行になり得る）は直接 Read しない。数値の根拠は `scripts/analyze_access.py` が出力する JSON のみとし、AI 側での再集計・推測を禁止する
- スクリプトが非ゼロ終了した場合（対象月のログが存在しない等）はエラーをそのままユーザーに報告して終了する
- HTML レポートは外部リソース参照なしの単一自己完結ファイルとし、末尾に raw JSON を `<details>` で埋め込んで監査可能にする

根拠: `commands/analyze-access.md:16-24`, `commands/analyze-access.md:33-63`

## 重要な設計判断とその理由

Facts（決定的な集計）と Opinions/Proposals（AI の解釈）を明確に分離するのは `commands/report-review.md` と同じパターン。数値の解釈にAIの推測が混ざることを防ぎ、集計ロジック自体は `scripts/analyze_access.py` の pytest で検証可能にすることで、レポートの信頼性を担保する。

生ログを直接読ませない設計は、`logs/access/*.log` が数千行規模になり得るため、context 消費とトークンコストを抑える目的もある。

## 統合ポイント

- 呼び出し元: `commands/work.md`（ルーティング判定後、または直接呼び出し）
- 呼び出すもの: `scripts/analyze_access.py`
- Codex wrapper: `skills/analyze-access/SKILL.md`
- 出力先: `logs/reports/access/`（`logs/` は `.gitignore` 対象）

## 注意事項・既知の制限

- 唯一の書き込みは `logs/reports/access/` 配下の新規 HTML ファイルのみ。既存ファイルの編集・削除、Git/GitHub の変更は行わない
- レポートファイルは `.gitignore` 対象のため PR には含まれない

## 変更履歴（git log より自動生成）

- d7a7627 feat(#212): add /analyze-access, /analyze-auto-approve, /analyze-token-usage log analysis commands
