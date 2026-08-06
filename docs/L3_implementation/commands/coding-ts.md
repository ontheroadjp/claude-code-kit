# `/coding-ts` specification

## 目的・役割

`coding-general`と`coding-js`にTypeScript固有の型安全性を重ねる。

## 動作の概要

strict modeを新規codeの基準とし、`any`、未検証assertion、non-null assertionを避ける。`enum`、`interface`、`type`は能力・runtime契約・既存規約に応じて選ぶ。

根拠: `commands/coding-ts.md:1-129`

## 重要な設計判断

legacy repositoryへの一括strict化や、正当な境界assertion・既存API互換まで全面禁止しない。型安全性と段階導入を両立する。

## 統合ポイント

TypeScript fileに適用され、TSXでは続けて`coding-react`、Next.jsではさらに`coding-nextjs`を読む。

## 注意事項・既知の制限

外部入力は型annotationだけでは検証されないためruntime validationが必要。
