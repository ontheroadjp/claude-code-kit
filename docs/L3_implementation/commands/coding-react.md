# `/coding-react` specification

## 目的・役割

JavaScript/TypeScript規約に、project非依存のReact原則と頻出anti-patternを重ねる。

## 動作の概要

pure render、Hook順序、minimal state、Effectの外部同期への限定、stable identity、測定に基づくmemo化、局所的state ownership、semantic HTML、user-visible testを規定する。

根拠: `commands/coding-react.md:1-43`

## 重要な設計判断

React version、renderer、frameworkの既存制約を優先し、特定state libraryやtest runnerを固定しない。最適化APIは正しさの前提にしない。

## 統合ポイント

JSXでは`coding-js`後、TSXでは`coding-ts`後に適用する。`coding-nextjs`の前提layerでもある。

## 注意事項・既知の制限

静的で並びもidentityも不変なlistではindex keyを例外的に許容する。
