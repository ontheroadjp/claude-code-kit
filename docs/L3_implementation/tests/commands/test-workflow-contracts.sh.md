# test-workflow-contracts.sh specification

## 目的・役割

`tests/commands/test-workflow-contracts.sh` は `/docs-sync`、`/init-docs`、`/task`、`/git-pr` 間の責務境界と HARD STOP 復旧契約を静的に検証する。

根拠: `tests/commands/test-workflow-contracts.sh:1-49`

## 動作の概要

Markdown command source of truth に必須の固定文字列が存在することを `rg --fixed-strings` で確認する。失敗件数を集計し、1件以上なら終了コード1、すべて成功なら終了コード0を返す。

根拠: `tests/commands/test-workflow-contracts.sh:12-49`

## 主要な検証契約

- `/docs-sync` が HARD STOP 時に documentation-only mode を自動委譲し、commit・結果書き出しへ復帰する
- `/init-docs` はモード指定なしで standalone、明示時だけ documentation-only とする
- documentation-only mode は現在ブランチを維持し、commit・push・PR 作成を行わない
- `/init-docs` standalone mode の Phase 7-3 が直接 commit せず `/git-commit` を `fixed_message` で呼び出す（issue #300）
- `/task` と `/patch` は、Git が返すブランチ名を Claude Code の installed `rename-thread.sh` に渡してスレッド名を更新する
- `/task` は `/docs-sync` 完了後に従来どおり `/git-pr` を実行し、`/git-pr` が PR 作成責務を保持する

根拠: `tests/commands/test-workflow-contracts.sh:26-42`

## 重要な設計判断

実行エンジンに依存する結合テストではなく command 文書の契約テストとすることで、Claude Code と Codex CLI が共通で読む source of truth の責務境界を直接固定する。

## 統合ポイント

- 検証対象: `commands/docs-sync.md`、`commands/init-docs.md`、`commands/task.md`、`commands/patch.md`、`commands/git-pr.md`
- 実行方法: `bash tests/commands/test-workflow-contracts.sh`
- lint: `shellcheck -x tests/commands/test-workflow-contracts.sh`

## 注意事項

固定文字列による契約テストであり、実際の GitHub PR 作成や branch 切り替えは行わない。

## 変更履歴（git log より自動生成）

- b37b6a6 fix(#344): add thread renaming helper
- ccd9fe3 wip: 2026-08-14 01:31:37 before apply_patch
- 5815389 refactor(#300): delegate init-docs commit to the shared commit workflow
- 65a9329 feat(#302): resume task after docs-sync hard stop
