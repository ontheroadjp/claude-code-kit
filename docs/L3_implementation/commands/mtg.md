# `commands/mtg.md`

## 目的・役割

`agenda` label の GitHub issue を、人間と AI agent が対話して検討する workflow。実装前の方向性、優先順位、フェーズ、実装範囲を人間が決定できる状態にする。

根拠: `commands/mtg.md:1-13`

## 動作概要

対象 issue の label を検証してから、目的、制約、既知の事実を起点に非線形の対話を進める。必要なフェーズだけ Facts / Assessment / Opinions / Proposals を使って具体化し、合意していない内容は決定事項として扱わない。

根拠: `commands/mtg.md:23-53`

`/mtg` の開始時には issue 本文に加えて全コメントを取得し、過去の議事録も対話の起点にする。今回の mtg の終了をユーザーが明示した場合は、日付・開始時刻・終了時刻を含む議事録を issue に投稿する。この投稿は close と独立しており、ユーザーが agenda issue の close を明示した場合だけ、決定事項、スコープ外、保留、実装 issue を要約して確認を受け、issue のコメント・close を行う。

根拠: `commands/mtg.md:23-85`

## 重要な設計判断

- fixed state machine を置かず、検討の途中で方向性・フェーズ・詳細・保留を自由に往復できるようにする。実装前の意思決定は直線的に進まないため。
- issue 起案は `/new-issue` の明示指示ゲートを維持する。AI の提案や合意を GitHub 変更の自動実行権限に変換しないため。
- close は人間専用の決定とする。AI が議論の十分性を判断して対話を打ち切らないため。
- 議事録の投稿と close を分離する。agenda issue は複数回の mtg をまたいで継続でき、各回の結果を issue コメントとして残せるようにするため。

## 統合ポイント

- 呼び出し元: `commands/work.md`
- Codex wrapper: `skills/mtg/SKILL.md`
- 実装 issue の起案: ユーザー明示指示時の `commands/new-issue.md`

## 注意事項・既知の制限

`/mtg` 自体は implementation workflow を開始せず、issue の起案後もユーザーが close を宣言するまで終了しない。ユーザーが今回の mtg の終了を宣言した場合は、agenda を close せずに議事録だけを投稿する。
