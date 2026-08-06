# `tests/commands/test-coding-guidelines.sh` specification

## 目的・役割

coding guidelineの合成関係、routing、代表anti-pattern、汎用性を静的に検証するcontract test。

## 動作の概要

固定文字列assertionでReact/Next.jsの依存順、Hook/key/client boundary/self-fetch/version確認、task/patch routingを検証する。全`commands/coding-*.md`にlocal absolute pathやrepository名が混入していないことも確認する。

根拠: `tests/commands/test-coding-guidelines.sh:1-52`

## 重要な設計判断

commandは実行codeではないため、重要な契約を軽量なstatic assertionで保護する。

## 統合ポイント

localでは`bash tests/commands/test-coding-guidelines.sh`、shell品質はShellCheckで検証する。

## 注意事項・既知の制限

文章の完全な意味妥当性ではなく、重要な契約とrepository非依存性のregressionを検出する。
