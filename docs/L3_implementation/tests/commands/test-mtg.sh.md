# `tests/commands/test-mtg.sh`

## 目的・役割

`/work` から `/mtg` への agenda routing と、ユーザー主導の対話境界を静的に検証する shell test。

根拠: `tests/commands/test-mtg.sh:1-57`

## 動作概要

固定文字列の存在・不在を検査し、exact `agenda` label routing、非線形の検討、Facts / Assessment / Opinions / Proposals による詳細化、明示指示だけでの `/new-issue`、ユーザーだけによる close を確認する。

根拠: `tests/commands/test-mtg.sh:39-53`

## 重要な設計判断

Markdown workflow は直接実行可能なプログラムではないため、安全上・運用上重要な文言を contract として固定する。

## 統合ポイント

- 対象: `commands/work.md`、`commands/mtg.md`、`skills/mtg/SKILL.md`
- 実行: `bash tests/commands/test-mtg.sh`

## 注意事項・既知の制限

静的検査であり、GitHub API を使った end-to-end routing は実行しない。
