# `skills/task/SKILL.md`

## 目的・役割

active parent workflow が ordinary または delegated issue-specific implementation を委譲した場合に `commands/task.md` を実行する adapter。

## 動作の概要

delegated mode では `/work` context を再利用し、plan approval から同じ worker で implementation、docs、validation、Ready PR 作成まで進む。merge、parent cleanup、stash restoration は行わない。

根拠: `skills/task/SKILL.md:1-27`

## 統合ポイント

- source: `commands/task.md`
- callers: `commands/work.md`, `commands/task-manager.md`

## 注意事項

standalone user entry として workflow authority を拡張しない。

## 変更履歴（git log より自動生成）

- f52dd59 feat(#400): unify work entry point
- 5863791 docs(skills): update command paths to use ~/.codex prefix
- 287dcc9 feat(#25): add skills/ directory and update repo.profile.json
