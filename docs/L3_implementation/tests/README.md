# tests/README.md — L3 per-file doc

## 目的・役割

`tests/` ディレクトリの構成・テスト対象・実行方法を説明するドキュメント。

## 動作の概要

- `tests/hooks/test-approval-hooks.sh` が検証するテストカテゴリ一覧を表で提示
- `tests/install/test-install.sh` の fixture installer contract と実行方法を記載
- 実行コマンドと終了コードの意味を記載
- 前提条件（依存ツール・実行環境）を明記
- task-manager orchestrationとgit-pr-merge deliveryのcontract testsをtest indexへ掲載

## 重要な設計判断

- テストは shell スクリプトで実装されており、外部テストフレームワーク不要
- installer test は fixture repository と一時 HOME を使い、実ユーザー環境を変更しない
- 全テスト PASS で exit 0、FAIL があれば exit 1 とするシンプルな規約を明示

## 統合ポイント

- テスト対象: hooks、command workflows、`commands/task-manager.md`、`commands/git-pr-merge.md`
- installer test 対象: `install.sh` の template symlink contract
- CI での実行は現時点では定義されていない（手動実行のみ）

根拠: `tests/README.md:1-88`, `tests/commands/test-task-manager.sh:1-132`, `tests/commands/test-git-pr-merge.sh:1-81`

## 変更履歴（git log より自動生成）

- 57dce6c feat(#389): add reviewed PR delivery workflow
- 446c4d3 #343 Replace report review with human-led mtg agendas (#345)
- 8beba5e docs: sync documentation
- 91067f8 docs: initialize project documentation (init-docs)
- 27f1861 feat(#76): install templates for claude and codex
- 3656e6e docs(#175): add README.md to each module directory
