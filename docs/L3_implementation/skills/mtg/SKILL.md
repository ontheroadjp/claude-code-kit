# `skills/mtg/SKILL.md`

## 目的・役割

Codex で `/mtg` を利用可能にする薄い wrapper。実際の workflow 定義は `commands/mtg.md` を唯一の source of truth とする。

根拠: `skills/mtg/SKILL.md:1-17`

## 動作概要

対応する command specification を読み、再解釈せずに実行する。`/new-issue` の開始と agenda の close は、いずれもユーザーの明示指示なしに行わない。

根拠: `skills/mtg/SKILL.md:13-25`

## 重要な設計判断

command と skill に別々の workflow を持たせず、Claude/Codex 間の仕様差分を防ぐ。

## 統合ポイント

- source of truth: `commands/mtg.md`
- 配布: `install.sh` が `skills/*/` を `~/.codex/skills/` へ symlink する

## 注意事項・既知の制限

ユーザーが close を宣言するまで、skill は agenda の対話を終了しない。
