# `skills/auto-approve-hazard-scan/SKILL.md`

## 目的・役割

Codex で `/auto-approve-hazard-scan` を利用可能にする薄い wrapper。実際の workflow 定義は `commands/auto-approve-hazard-scan.md` を唯一の source of truth とする。

根拠: `skills/auto-approve-hazard-scan/SKILL.md:1-19`

## 動作概要

対応する command specification を読み、その内容を再解釈・簡略化せずに実行する。command が存在しない場合は処理を停止する。

根拠: `skills/auto-approve-hazard-scan/SKILL.md:12-15`

## 重要な設計判断

command と skill に別々の workflow を持たせず、Claude/Codex 間の仕様差分を防ぐ。wrapper 側にも scope guard を置き、`hooks/auto-approve-readonly.sh` を含む既存コードの変更、ユーザーの明示的なバッチ承認なしの GitHub issue/label 操作、および `/work` の自動起動を禁止する（`commands/auto-approve-hazard-scan.md` 本体のバッチ承認・スコープ外方針と重複して明記することで、wrapper 単独でも安全側に倒れるようにしている）。

根拠: `skills/auto-approve-hazard-scan/SKILL.md:17-22`

## 統合ポイント

- source of truth: `commands/auto-approve-hazard-scan.md`
- 配布: `install.sh` が `skills/*/` を `~/.codex/skills/` へ symlink する

## 注意事項・既知の制限

`commands/auto-approve-hazard-scan.md` と同一のスコープ制約（hook不変更・issue作成前のバッチ承認必須）を持つ。詳細は `docs/L3_implementation/commands/auto-approve-hazard-scan.md` を参照。

## 変更履歴（git log より自動生成）

（初回追加のためコミット前。次回 /docs-sync 実行時に自動反映される）
