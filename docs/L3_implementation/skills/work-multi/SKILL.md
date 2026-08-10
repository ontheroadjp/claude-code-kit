# `skills/work-multi/SKILL.md`

## 目的・役割

Codex で `/work-multi` を利用可能にする薄い wrapper。実際の workflow 定義は `commands/work-multi.md` を唯一の source of truth とする。

根拠: `skills/work-multi/SKILL.md:1-23`

## 動作概要

`commands/work-multi.md` を読み、その内容を再解釈・簡略化せずに実行する。command が存在しない場合は処理を停止する。

根拠: `skills/work-multi/SKILL.md:12-17`

## 重要な設計判断

`skills/work/SKILL.md` と全く同じパターンを踏襲し、command と skill に別々の workflow を持たせないことで Claude/Codex 間の仕様差分を防ぐ（issue #296）。

根拠: `skills/work-multi/SKILL.md:19-22`

## 統合ポイント

- source of truth: `commands/work-multi.md`
- 配布: `install.sh` が `skills/*/` を `~/.codex/skills/` へ symlink する

## 注意事項・既知の制限

`commands/work-multi.md` が欠落・読み取り不能な場合は work-multi workflow を実行できない旨を報告するに留める。

## 変更履歴（git log より自動生成）

- bc4ae7b feat(#296): add /work-multi worktree-isolated entry point
