# `/coding-js` specification

## 目的・役割

`coding-general`にJavaScript固有の安全な既定値を重ねる。

## 動作の概要

既存toolchainを優先し、`const`/`let`、strict equality、意味に合う関数形式、欠如を隠さないoptional chaining、error処理を規定する。

根拠: `commands/coding-js.md:1-85`

## 重要な設計判断

Biome/Vitestやarrow functionを全面強制せず、新規選定時の候補と文脈依存の構文選択に位置づける。

## 統合ポイント

`coding-ts`、`coding-react`、`coding-nextjs`の前提layer。

## 注意事項・既知の制限

欠如が契約違反の場合、`?.`で失敗を隠さず明示的にvalidationする。
