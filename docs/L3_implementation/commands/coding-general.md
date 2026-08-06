# `/coding-general` specification

## 目的・役割

言語・frameworkに依存しない実装原則を定義し、すべての`coding-*` layerの基礎となる。

## 動作の概要

一次情報によるAPI確認、重大な不明点の確認、既存patternの尊重、単一責任、errorの握り潰し防止、意味を持つliteralの定数化を要求する。既存repositoryのruntime・設定・toolchainを本ガイドの既定値より優先する。

根拠: `commands/coding-general.md:1-52`

## 重要な設計判断

汎用性を保つため、明白な一回限りの値まで定数化せず、既存コードから一意に判断できる事項まで質問に戻さない。規約適用だけを理由にtoolchainを追加・置換しない。

## 統合ポイント

すべての言語・framework別`coding-*` commandから最初に参照される。

## 注意事項・既知の制限

対象repositoryの規約が安全性を損なう場合は黙って従わず、根拠と代案を提示する。
