# `tests/commands/test-mtg.sh`

## 目的・役割

`/work` から `/mtg` への agenda routing、ユーザー主導の対話境界、issue 履歴と議事録の契約を静的に検証する shell test。

根拠: `tests/commands/test-mtg.sh:1-57`

## 動作概要

固定文字列の存在・不在を検査し、exact `agenda` label routing、非線形の検討、Facts / Assessment / Opinions / Proposals による詳細化、全コメントの取得、日付・開始時刻・終了時刻を含む議事録、明示指示だけでの `/new-issue`、ユーザーだけによる close を確認する。

根拠: `tests/commands/test-mtg.sh:39-53`

## 重要な設計判断

Markdown workflow は直接実行可能なプログラムではないため、安全上・運用上重要な文言を contract として固定する。

## 統合ポイント

- 対象: `commands/work.md`、`commands/mtg.md`、`skills/mtg/SKILL.md`
- 実行: `bash tests/commands/test-mtg.sh`

## 注意事項・既知の制限

静的検査であり、GitHub API を使った end-to-end routing は実行しない。

## 変更履歴（git log より自動生成）

- 9f02f04 docs(#347): record mtg minutes
- 446c4d3 #343 Replace report review with human-led mtg agendas (#345)
