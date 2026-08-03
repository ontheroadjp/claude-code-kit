# hooks/lib/README.md — L3 per-file doc

## 目的・役割

`hooks/lib/` ディレクトリの役割と `approval-safety.sh` の使い方を開発者向けに説明するドキュメント。

## 動作の概要

- `approval-safety.sh` が提供する `approval_safety_destructive_reason` 関数のシグネチャと検出対象を表で示す
- hook script からの `source` による利用例をコードスニペットで説明

## 重要な設計判断

- 破壊的操作の判定リストは `hooks/lib/approval-safety.sh` が正となり、README はその一覧を人間可読な形で転記する
- README が `approval-safety.sh` の仕様と乖離しないよう、`approval-safety.sh` を変更した際は本ファイルも更新すること

## 統合ポイント

- 参照元: `hooks/auto-approve-readonly.sh`、`hooks/guard-destructive-cmd.sh`（実際に source する）
- 関連: `docs/L3_implementation/hooks/auto_approve_readonly.md`

根拠: `hooks/lib/README.md:1-55`, `hooks/lib/approval-safety.sh:1-87`

## 変更履歴（git log より自動生成）

- db6d6c3 fix(#210): resolve session id from env instead of a shared pointer file
- 3656e6e docs(#175): add README.md to each module directory
