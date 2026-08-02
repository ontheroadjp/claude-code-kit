# `commands/report-review.md`

## 目的・役割

`report` label の GitHub issue を read-only で評価し、確認した事実、評価、意見、提案、リスクと未確認事項を標準出力へ提示する。通常は `/work #N` から委譲される。

根拠: `commands/report-review.md:1-14`

## 動作概要

GitHub CLI の認証と issue 番号を確認し、title、body、labels、URL、state を取得する。label name が `report` と完全一致しない issue は対象外として終了する。

根拠: `commands/report-review.md:20-37`

対象 issue の主張を分解し、repo profile、primary investigation doc、report が言及するファイルの順で必要な根拠だけを読む。対象を特定できない場合に限って検索を使い、候補ファイルを直接確認する。

根拠: `commands/report-review.md:39-49`

評価結果は Facts、Assessment、Opinions、Proposals、Risks and Unknowns に分離した固定形式で標準出力へ提示する。

根拠: `commands/report-review.md:51-91`

## 重要な設計判断

- report 原文、確認済みの事実、AI の見解を分離し、未確認の主張を事実として扱わない。
- 提案には優先度、理由、期待効果を含めるが、実装計画や変更作業には移行しない。
- 評価結果を issue comment に自動投稿せず、利用者が確認できる標準出力だけに限定する。

## 統合ポイント

- 呼び出し元: `commands/work.md`
- 調査起点: `docs/.ai/repo.profile.json` と `primary_docs.investigation`
- Codex wrapper: `skills/report-review/SKILL.md`

## 注意事項・既知の制限

- ファイル、Git state、GitHub issue / PR を一切変更しない。
- `report` label の追加や他 workflow への切り替えも自動では行わない。
- 変更が必要という結論になっても、実行せず proposal として提示する。

根拠: `commands/report-review.md:5-14`, `commands/report-review.md:34-36`, `commands/report-review.md:61-91`
