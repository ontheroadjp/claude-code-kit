# /coding-sh

まず `coding-general` を参照し、その後以下の shell script 固有ルールを適用すること。

---

## ツールチェーン

- **Linter**: ShellCheck（CI で全 `*.sh` に対して実行。ローカル確認は `shellcheck -x <file>...`）

---

## 原則

### 1. shebang は `#!/bin/bash` を使う

新規スクリプトの shebang は `#!/bin/bash` とする。

```bash
# 悪い例
#!/bin/sh

# 良い例
#!/bin/bash
```

### 2. 直接実行するスクリプトは先頭で `set -euo pipefail` を宣言する

エラーの握り潰しを防ぐため、shebang の直後で `set -euo pipefail` を宣言する。

```bash
# 悪い例
#!/bin/bash

payload=$(cat)

# 良い例
#!/bin/bash
set -euo pipefail

payload=$(cat)
```

**例外1: source される共有ライブラリ（例: `hooks/lib/*.sh`）には書かない。** `set` はシェルオプションであり、`source` されたファイル内で設定すると呼び出し元シェルのオプションまで書き換えてしまう。オプション管理は呼び出し元スクリプトの責務とする。

**例外2: 意図的にエラーを握り潰さなければならない場合**（例: ベストエフォートのログ記録 hook で、失敗しても呼び出し元の処理を止めてはならない）は `set -euo pipefail` を省略してよいが、coding-general の原則 5（例外の握り潰し禁止）に従い、なぜ省略しているかをファイル先頭のコメントで明示すること。

### 3. 変数展開は常にダブルクオートする

意図的な word splitting / glob 展開が必要な場合を除き、変数展開は `"$var"` の形でクオートする。

```bash
# 悪い例
[ $i -gt 0 ] && result+="$SEP"

# 良い例
[ "$i" -gt 0 ] && result+="$SEP"
```

### 4. 単純な文字列置換に `echo | sed` を使わない — パラメータ展開を使う

`sed` の呼び出しコストと不要なサブシェルを避けるため、単純な置換にはパラメータ展開を使う。

```bash
# 悪い例
file_path=$(echo "$file_path" | sed "s|${HOME}|~|g")

# 良い例
file_path=${file_path//$HOME/\~}
```

### 5. ShellCheck の指摘には対応するか、理由を添えて抑制する

ShellCheck が指摘した箇所は原則として修正する。指摘が意図的な書き方に対する誤検知の場合のみ抑制してよい。

- 単発の誤検知: 対象行の直前に `# shellcheck disable=<コード>` を書く
- ファイル全体で繰り返し出る誤検知（例: awk スクリプトやテストフィクスチャとして意図的に単一引用符を使っている場合の `SC2016`）: `set -euo pipefail` の直後にファイル単位の `# shellcheck disable=<コード>` を書く
- リポジトリ全体を対象にした `.shellcheckrc` によるルール無効化は行わない（誤検知以外のケースまで無効化してしまうため）

```bash
# 悪い例（理由なしに抑制）
# shellcheck disable=SC2016
text=$(printf '*%s*\n%s' "$title" "$body")

# 良い例（printf のフォーマット文字列を意図的に単一引用符にしている）
# shellcheck disable=SC2016  # printf format string; $ must stay literal
text=$(printf '*%s*\n%s' "$title" "$body")
```
