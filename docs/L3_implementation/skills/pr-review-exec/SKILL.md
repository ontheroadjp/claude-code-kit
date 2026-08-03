# pr-review-exec skill specification

## 目的・役割

`skills/pr-review-exec/SKILL.md` は Codex が `/pr-review-exec` を利用するための薄い wrapper である。workflow の唯一の正本を `~/.codex/commands/pr-review-exec.md` と定義し、skill 自体には review ロジックを重複させない。

根拠: `skills/pr-review-exec/SKILL.md:1-14`

## 動作の概要

1. workflow 開始時に `commands/pr-review-exec.md` を1回読む
2. 正本の内容を省略・再解釈せず実行する
3. `/work`・`/task`・`/patch`・`/pr-review`・`/review-resolve` をこの workflow から呼び出さない

根拠: `skills/pr-review-exec/SKILL.md:12-16`

## 重要な設計判断

`skills/pr-review/SKILL.md` と同じパターンで、Claude commands と Codex skills の挙動差を防ぐため詳細仕様は command に集約する。skill から source of truth を編集することも禁止し、実行中の自己変更を避ける。

根拠: `skills/pr-review-exec/SKILL.md:18-22`

## 統合ポイント

- 読み込み先: `~/.codex/commands/pr-review-exec.md`
- 配置元: `skills/pr-review-exec/SKILL.md`
- 呼び出し元: `commands/pr-review.md` が起動する Codex reviewer subprocess
- installer: `install.sh` の `skills/*/` symlink loop により `~/.codex/skills/` へ公開される

## 注意事項・既知の制限

- command が missing/unreadable の場合は workflow を実行しない
- review の具体的な gate と終了条件は command 側だけで管理する
- ファイル編集・git write 操作・他コマンド呼び出しはこの skill からも行わない

## 変更履歴（git log より自動生成）

- 14b4255 refactor(#203): decouple pr-review reviewer execution into pr-review-exec
