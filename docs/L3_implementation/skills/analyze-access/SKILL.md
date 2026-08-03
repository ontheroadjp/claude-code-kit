# `skills/analyze-access/SKILL.md`

## 目的・役割

Codex で `/analyze-access` を利用可能にする薄い wrapper。実際の workflow 定義は `commands/analyze-access.md` を唯一の source of truth とする。

根拠: `skills/analyze-access/SKILL.md:1-19`

## 動作概要

対応する command specification を読み、その内容を再解釈・簡略化せずに実行する。command が存在しない場合は処理を停止する。

根拠: `skills/analyze-access/SKILL.md:9-16`

## 重要な設計判断

command と skill に別々の workflow を持たせず、Claude/Codex 間の仕様差分を防ぐ。wrapper 側にも scope guard を置き、`logs/reports/access/` 配下の新規 HTML 以外のファイル作成・編集・削除、および Git/GitHub の変更を禁止する。

根拠: `skills/analyze-access/SKILL.md:18-25`

## 統合ポイント

- source of truth: `commands/analyze-access.md`
- 配布: `install.sh` が `skills/*/` を `~/.codex/skills/` へ symlink する

## 注意事項・既知の制限

生ログを直接読まず、`scripts/analyze_access.py` が出力する JSON のみを分析の根拠とする。
