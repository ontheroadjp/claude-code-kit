# `skills/triage-issues-for-auto-approve/SKILL.md`

## 目的・役割

Codex で `/triage-issues-for-auto-approve` を利用可能にする薄い wrapper。実際の workflow 定義は `commands/triage-issues-for-auto-approve.md` を唯一の source of truth とする。

根拠: `skills/triage-issues-for-auto-approve/SKILL.md:1-19`

## 動作概要

対応する command specification を読み、その内容を再解釈・簡略化せずに実行する。command が存在しない場合は処理を停止する。

根拠: `skills/triage-issues-for-auto-approve/SKILL.md:11-14`

## 重要な設計判断

command と skill に別々の workflow を持たせず、Claude/Codex 間の仕様差分を防ぐ。wrapper 側にも scope guard を置き、`commands/triage-issues.md` との混同禁止、GitHub issue/label/PR 操作の禁止、`/work` の自動起動禁止を明記する（`commands/triage-issues-for-auto-approve.md` 本体の read-only 方針・スコープ外方針と重複して明記することで、wrapper 単独でも安全側に倒れるようにしている）。

根拠: `skills/triage-issues-for-auto-approve/SKILL.md:16-21`

## 統合ポイント

- source of truth: `commands/triage-issues-for-auto-approve.md`
- 配布: `install.sh` が `skills/*/` を `~/.codex/skills/` へ symlink する

## 注意事項・既知の制限

`commands/triage-issues-for-auto-approve.md` と同一のスコープ制約（read-only、`/work` 自動起動禁止）を持つ。詳細は `docs/L3_implementation/commands/triage-issues-for-auto-approve.md` を参照。

## 変更履歴（git log より自動生成）

- 7aa4615 feat(#285): add /triage-issues-for-auto-approve command
