# skills/coding-sh/SKILL.md specification

## 目的・役割

Codex CLI 向けの薄い wrapper。`commands/coding-sh.md` を Source of Truth として Read するよう指示するだけで、ロジックは持たない。`skills/coding-py/SKILL.md` と同型（依存する他の coding skill はない）。

根拠: `skills/coding-sh/SKILL.md:1-24`

## 動作の概要

1. `commands/coding-general.md` を Read し、言語非依存の原則を適用する
2. `commands/coding-sh.md` を Read し、shell script 固有のルールを重ねて適用する
3. ソースファイルの指示を再解釈・省略・拡張しない。自分の前提と矛盾する場合はソースファイルに従う

## 統合ポイント

- Source of Truth: `commands/coding-sh.md`
- install: `install.sh` が `skills/*/` を検出して `~/.codex/skills/coding-sh/` に自動 symlink する（この skill 追加のために `install.sh` 自体の変更は不要）

## 注意事項・既知の制限

- このスキルから `commands/coding-sh.md` / `commands/coding-general.md` を編集しない
- いずれかのファイルが見つからない・読めない場合は、復元されるまで coding-sh ワークフローを実行できない旨を報告する
