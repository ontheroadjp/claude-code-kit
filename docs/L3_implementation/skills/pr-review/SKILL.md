# pr-review skill specification

## 目的・役割

`skills/pr-review/SKILL.md` は Codex が `/pr-review` を利用するための薄い wrapper である。workflow の唯一の正本を `~/.codex/commands/pr-review.md` と定義し、skill 自体には review ロジックを重複させない。

根拠: `skills/pr-review/SKILL.md:1-16`

## 動作の概要

1. workflow 開始時に `commands/pr-review.md` を1回読む
2. 正本の内容を省略・再解釈せず実行する
3. merge、branch 削除、main 同期を人間の管理下に保つ

根拠: `skills/pr-review/SKILL.md:12-17`

## 重要な設計判断

Claude commands と Codex skills の挙動差を防ぐため、詳細仕様は command に集約する。skill から source of truth を編集することも禁止し、実行中の自己変更を避ける。

根拠: `skills/pr-review/SKILL.md:8-22`

## 統合ポイント

- 読み込み先: `~/.codex/commands/pr-review.md`
- 配置元: `skills/pr-review/SKILL.md`
- installer: `install.sh` の `skills/*/` symlink loop により `~/.codex/skills/` へ公開される

## 注意事項・既知の制限

- command が missing/unreadable の場合は workflow を実行しない
- review の具体的な gate と終了条件は command 側だけで管理する

## 変更履歴（git log より自動生成）

- d94812c feat(#185): add autonomous cross-agent PR review workflow
