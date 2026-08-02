# test-pr-review.sh specification

## 目的・役割

`tests/commands/test-pr-review.sh` は `/pr-review` と `/git-pr` の宣言的 workflow contract を静的に検証する shell test である。Markdown command は直接実行可能なプログラムではないため、安全上重要な必須句と禁止コマンドを固定する。

根拠: `tests/commands/test-pr-review.sh:1-10`, `tests/commands/test-pr-review.sh:38-53`

## 動作の概要

`rg --fixed-strings` を使う `assert_contains` と `assert_absent` により、command/skill の契約を検査する。全 case を実行して failure 数を集計し、1件以上なら exit 1、全件成功なら exit 0 を返す。

根拠: `tests/commands/test-pr-review.sh:12-36`, `tests/commands/test-pr-review.sh:55-60`

## 検証対象

- 最大3ラウンド
- Claude/Codex の相互 routing
- review と HEAD SHA の結合
- GitHub APPROVED / CHANGES_REQUESTED 投稿
- reviewer identity と Claude read-only tools
- session-approved による修正範囲制限
- merge、main checkout/pull、branch deletion の禁止
- `/git-pr` から `/pr-review` への handoff
- skill の source-of-truth path

根拠: `tests/commands/test-pr-review.sh:38-53`

## 重要な設計判断

禁止操作は command の説明文ではなく、実行可能な shell 断片として現れる固定文字列を検出する。必須要素と禁止要素を同じ test で扱うことで、「機能追加時に安全境界だけ脱落する」変更を検知する。

## 統合ポイント

- 対象: `commands/pr-review.md`、`commands/git-pr.md`、`skills/pr-review/SKILL.md`
- 実行: `bash tests/commands/test-pr-review.sh`
- 依存: Bash、ripgrep (`rg`)

## 注意事項・既知の制限

- 静的 contract test であり、外部 CLI や GitHub API の実通信は行わない
- 文言変更時は意図した契約変更か確認して test pattern も更新する

## 変更履歴（git log より自動生成）

- d94812c feat(#185): add autonomous cross-agent PR review workflow
