# /coding-react

まず `coding-general`、`coding-js`、TypeScriptの場合は `coding-ts` を参照し、その後以下のReact固有ルールを適用すること。対象プロジェクトが使用するReact version、renderer、frameworkの公式資料と既存規約を優先する。

---

## 原則とアンチパターン

### 1. renderは純粋に保つ

render中に外部状態を変更しない。DOM操作、network request、subscription、timerなどはevent handlerまたは適切なEffectに置く。入力から計算できる値をEffectで同期して二重管理しない。

### 2. Hookの呼び出し順を変えない

Hookを条件分岐、loop、nested function、早期return後から呼び出さない。条件はHookの内側へ移すか、責務ごとにcomponentを分割する。lint ruleを無効化して回避しない。

### 3. stateを最小化する

propsや既存stateからrender時に導出できる値、単なるcache、イベント発生時だけ必要な値をstateへ複製しない。相互に矛盾しうる複数stateより、単一のsource of truthを選ぶ。

### 4. Effectをイベント処理の代用にしない

ユーザー操作により起きる処理は、そのevent handlerで実行する。Effectは外部systemとの同期に限定し、依存配列の省略、lint抑制、毎renderで変化するobject/functionへの無自覚な依存を避ける。cleanupはsetupと対称にする。

### 5. componentのidentityを安定させる

list keyにindex、乱数、render時刻を使わない（順序もidentityも不変な静的listを除く）。component定義を親componentのrender内に置いて意図しないremountを起こさない。

### 6. memo化を正しさのために使わない

`memo`、`useMemo`、`useCallback`がなくても正しく動く設計にする。測定された再renderコスト、参照同一性の契約、framework/compilerの要件がある場合に限定し、惰性で全面適用しない。

### 7. stateの所有範囲を狭くする

一箇所だけで使うstateをglobal storeやroot Contextへ置かない。頻繁に変化する巨大Context、万能provider、深いprop drillingの機械的なContext化を避け、compositionまたは関心ごとの分割を使う。

### 8. platform semanticsを保つ

click可能な`div`でbuttonやlinkを再実装しない。semantic HTML、keyboard操作、focus、label、loading/error/empty stateを設計に含める。dangerouslySetInnerHTMLへ未検証入力を渡さない。

### 9. user-visible behaviorをテストする

component内部state、private function、CSS classだけに結合したテストを避ける。ユーザーが認識するrole、label、text、interactionとaccessibilityを検証する。Effectや非同期更新を根拠なく固定時間sleepで待たない。
