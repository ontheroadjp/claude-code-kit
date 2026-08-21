# `tests/commands/test-git-pr-merge.sh`

## 目的・役割

`commands/git-pr-merge.md`と`skills/git-pr-merge/SKILL.md`のreviewed PR deliveryに関する安全契約を固定文字列で検証するshell contract testである。

根拠: `tests/commands/test-git-pr-merge.sh:1-41`

## 動作の概要

`assert_exists`、`assert_contains`、`assert_absent`を用い、standalone/delegated approval、approved-head drift、known/unknown commit、latest-main refresh、CI/local fallback、conflict repair、Draft/Ready、squash verification、workspace invariantを検証する。

根拠: `tests/commands/test-git-pr-merge.sh:10-79`

## 重要な設計判断

Markdown workflowは直接実行可能なprogramではないため、repository既存のcommand contract test方式に合わせてsource-of-truthの必須文言と禁止コマンドを検証する。local main禁止はpositive invariantに加え、checkout/switch/direct push文字列のabsenceでも固定する。

## 統合ポイント

- targets: `commands/git-pr-merge.md`, `skills/git-pr-merge/SKILL.md`
- execution: `bash tests/commands/test-git-pr-merge.sh`
- lint: `shellcheck -x tests/commands/test-git-pr-merge.sh`

## 注意事項・既知の制限

GitHub上で実PRを作成・mergeするend-to-end testではなく、static workflow contract testである。
