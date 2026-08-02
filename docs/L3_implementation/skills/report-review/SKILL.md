# `skills/report-review/SKILL.md`

## 目的・役割

Codex で `/report-review` を利用可能にする薄い wrapper。実際の workflow 定義は `commands/report-review.md` を唯一の source of truth とする。

根拠: `skills/report-review/SKILL.md:1-17`

## 動作概要

対応する command specification を読み、その内容を再解釈・簡略化せずに実行する。command が存在しない場合は処理を停止する。

根拠: `skills/report-review/SKILL.md:8-22`

## 重要な設計判断

command と skill に別々の workflow を持たせず、Claude/Codex 間の仕様差分を防ぐ。wrapper 側にも read-only scope guard を置き、ファイル、Git、GitHub の変更を禁止する。

根拠: `skills/report-review/SKILL.md:10-25`

## 統合ポイント

- source of truth: `commands/report-review.md`
- 配布: `install.sh` が `skills/*/` を `~/.codex/skills/` へ symlink する

## 注意事項・既知の制限

評価は標準出力だけに提示し、永続化や GitHub 投稿は行わない。

根拠: `skills/report-review/SKILL.md:19-25`
