# `/coding-nextjs` specification

## 目的・役割

TypeScript・React規約に、version変化を考慮したNext.js原則と頻出anti-patternを重ねる。

## 動作の概要

最小client boundary、serverからdata sourceへの直接access、実行地点での認可、明示的cache/freshness、意図したrendering mode、route segmentの責務分離、secretのbundle分離、安全なmutation、framework機能の適切な利用を規定する。

根拠: `commands/coding-nextjs.md:1-43`

## 重要な設計判断

変化しやすいAPI名やcache semanticsを固定せず、導入済みversionの公式docs・型・build diagnosticsで検証する。server-side self-fetchはHTTP境界自体をtestする場合のみ例外とする。

## 統合ポイント

`next` dependencyまたはNext.js configを持つprojectで、言語規約と`coding-react`の後に適用する。

## 注意事項・既知の制限

middlewareやUI非表示だけを認可controlとして扱わない。client由来のidentityや価格はserverで再検証する。
