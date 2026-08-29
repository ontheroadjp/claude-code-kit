# `skills/work/SKILL.md`

## 目的・役割

Codex が user-requested `/work` を実行する adapter。単一・複数 issue の唯一の implementation entry と session owner であることを固定する。

## 動作の概要

`commands/work.md` を完全に読み、complete input の atomic validation、project context handoff、workspace cleanup/stash restoration ownership を維持して実行する。

根拠: `skills/work/SKILL.md:1-28`

## 統合ポイント

- source: `commands/work.md`
- multi-issue delegate: `skills/task-manager/SKILL.md`
- issue worker: `skills/task/SKILL.md`

## 注意事項

adapter は workflow を再解釈せず、command source を直接編集しない。
