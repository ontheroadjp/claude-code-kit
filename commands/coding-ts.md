# /coding-ts

まず `coding-general` と `coding-js` を参照し、その後以下の TypeScript 固有ルールを適用すること。

---

## ツールチェーンの既定値

- 既存プロジェクトの linter、formatter、test runner、`tsconfig.json` を優先する。
- 新規設定では TypeScript の `strict` mode を既定とし、無効化が必要なら互換性上の理由と移行範囲を明示する。

---

## 原則

### 1. 新規コードは strict mode を基準にする

新規プロジェクトでは `strict: true` を有効にする。既存プロジェクトで無効な場合、規約適用の副作用として全体を切り替えず、変更箇所の型安全性を保ちながら段階的な有効化を提案する。

```json
// 悪い例
{
  "compilerOptions": {
    "noImplicitAny": true,
    "strictNullChecks": true
  }
}

// 良い例
{
  "compilerOptions": {
    "strict": true
  }
}
```

### 2. `any` 原則禁止 — `unknown` を使う

`any` を使うと型チェックが無効になる。型が不明な値には `unknown` を使い、型ガードで絞り込む。

```ts
// 悪い例
function parse(data: any) {
  return data.value;
}

// 良い例
function parse(data: unknown) {
  if (typeof data === 'object' && data !== null && 'value' in data) {
    return (data as { value: unknown }).value;
  }
  throw new Error('不正なデータ形式');
}
```

### 3. 根拠のない型アサーションを避ける

外部入力を検証せず `as` で目的の型にすることは禁止する。型ガード、schema validation、`satisfies` を優先する。DOM APIなど、実行時条件を確認済みでTypeScriptが表現できない境界では、狭い範囲のアサーションと根拠を許容する。

```ts
// 悪い例
const user = response as User;

// 良い例
function isUser(value: unknown): value is User {
  return (
    typeof value === 'object' &&
    value !== null &&
    typeof (value as Record<string, unknown>).id === 'string'
  );
}
if (isUser(response)) {
  // ここで response は User 型
}
```

### 4. 非 null アサーション（`!`）禁止

`value!` は実行時エラーの原因になる。`??` / `?.` またはガード節で明示的に処理する。

```ts
// 悪い例
const name = user!.name;

// 良い例
const name = user?.name ?? '名無し';
```

### 5. `enum` を惰性で導入しない

型だけが必要なら string union、値と型の両方が必要なら `as const` objectを優先する。既存APIとの互換、numeric protocol、明示的なruntime objectが必要な場合まで `enum` を禁止しない。

```ts
// 悪い例
enum Direction {
  Up = 'UP',
  Down = 'DOWN',
}

// 良い例（値が必要な場合）
const Direction = {
  Up: 'UP',
  Down: 'DOWN',
} as const;
type Direction = typeof Direction[keyof typeof Direction];

// 良い例（型だけでよい場合）
type Direction = 'UP' | 'DOWN';
```

### 6. `interface` と `type` は能力と既存規約で選ぶ

- declaration mergingや`implements`中心の公開契約には `interface` が適する。
- union、intersection、mapped type、conditional typeには `type` を使う。
- 単純なobject shapeはどちらも正しいため、リポジトリ内の一貫性を優先する。

```ts
// 悪い例（ユニオンに interface は使えない）
interface Result = Success | Failure; // 構文エラー

// 良い例
interface User {
  id: string;
  name: string;
}

type Result = Success | Failure;
type UserId = string;
```
