# test-workflow-contracts.sh specification

## 目的・役割

`tests/commands/test-workflow-contracts.sh` は `/docs-sync`、`/init-docs`、`/task`、`/git-pr` 間の責務境界と HARD STOP 復旧契約を静的に検証する。

根拠: `tests/commands/test-workflow-contracts.sh:1-48`

## 動作の概要

Markdown command source of truth に必須の固定文字列が存在することを `rg --fixed-strings` で確認する。失敗件数を集計し、1件以上なら終了コード1、すべて成功なら終了コード0を返す。

根拠: `tests/commands/test-workflow-contracts.sh:12-48`

## 主要な検証契約

- `/docs-sync` が HARD STOP 時に documentation-only mode を自動委譲し、commit・結果書き出しへ復帰する
- `/init-docs` はモード指定なしで standalone、明示時だけ documentation-only とする
- documentation-only mode は現在ブランチを維持し、commit・push・PR 作成を行わない
- `/task` は `/docs-sync` 完了後に従来どおり `/git-pr` を実行し、`/git-pr` が PR 作成責務を保持する

根拠: `tests/commands/test-workflow-contracts.sh:25-42`

## 重要な設計判断

実行エンジンに依存する結合テストではなく command 文書の契約テストとすることで、Claude Code と Codex CLI が共通で読む source of truth の責務境界を直接固定する。

## 統合ポイント

- 検証対象: `commands/docs-sync.md`、`commands/init-docs.md`、`commands/task.md`、`commands/git-pr.md`
- 実行方法: `bash tests/commands/test-workflow-contracts.sh`
- lint: `shellcheck -x tests/commands/test-workflow-contracts.sh`

## 注意事項

固定文字列による契約テストであり、実際の GitHub PR 作成や branch 切り替えは行わない。

## 変更履歴（git log より自動生成）
