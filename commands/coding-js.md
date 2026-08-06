# /coding-js

まず `coding-general` を参照し、その後以下の JavaScript 固有ルールを適用すること。

---

## ツールチェーンの既定値

- 新規プロジェクトで選択が未確定の場合は Biome と Vitest を候補にする。
- 既存プロジェクトでは `package.json`、設定ファイル、lockfile、CI が示すツールを使い、規約適用だけを理由に置換しない。

---

## 原則

### 1. `var` 禁止 — `const` / `let` のみ使用する

`var` は使用しない。再代入が必要な場合は `let`、それ以外は常に `const` を使う。

```js
// 悪い例
var count = 0;

// 良い例
let count = 0;
const MAX = 100;
```

### 2. `==` 禁止 — 厳密等価演算子 `===` を使う

型強制による予期しない比較を防ぐため、`==` / `!=` は使用しない。常に `===` / `!==` を使う。

```js
// 悪い例
if (value == null) { ... }

// 良い例
if (value === null) { ... }
```

### 3. 関数形式は意味に合わせる

短いコールバックや lexical `this` が必要な関数にはアロー関数を使う。hoisting、名前付きスタックトレース、generator、動的 `this` が必要な場合は `function` を使う。見た目だけを理由に既存形式を一括変換しない。

```js
// 悪い例
const doubled = items.map(function(x) { return x * 2; });

// 良い例
const doubled = items.map((x) => x * 2);
```

### 4. `?.` / `??` で値の欠如を正しく扱う

欠如を許容するアクセスには `?.`、`null` / `undefined` だけを既定値に置き換える場合は `??` を使う。欠如が契約違反なら、オプショナルチェーンで隠さず検証して失敗させる。

```js
// 悪い例
const name = user && user.profile && user.profile.name;
const display = name !== null && name !== undefined ? name : 'Guest';

// 良い例
const name = user?.profile?.name;
const display = name ?? 'Guest';
```

### 5. 例外の握り潰し禁止

例外を処理せずに飲み込んではならない。空の `catch {}` や、ログも再 throw もない `catch (e) {}` は禁止。

- エラーを本当に無視してよい場合は、その理由をコメントで明示する。

```js
// 悪い例
try {
  connect();
} catch (e) {}

// 良い例
try {
  connect();
} catch (e) {
  logger.warn('接続に失敗しました。リトライします', e);
}
```
