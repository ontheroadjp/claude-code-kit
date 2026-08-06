# `/coding-py` specification

## 目的・役割

`coding-general`にPython固有の型・例外・test規約を重ねる。

## 動作の概要

公開境界と変更codeへの型annotation、`Any`の局所化、具体的な例外処理、意味を持つliteralの定数化、単一責任、導入済みtest frameworkの尊重を定義する。

根拠: `commands/coding-py.md:1-93`

## 重要な設計判断

ruff、mypy、pytestは未選定時の候補であり、legacy code全体や既存suiteを局所変更の副作用として移行しない。

## 統合ポイント

task/patchが`.py`変更前に読む。

## 注意事項・既知の制限

`Any`の利用理由と`# type: ignore`は別に評価し、不正なignoreでerrorを隠さない。
