# /coding-py

まず `coding-general` を参照し、その後以下の Python 固有ルールを適用すること。

---

## ツールチェーンの既定値

- 新規プロジェクトで選択が未確定の場合は ruff、mypy、pytest を候補にする。
- 既存プロジェクトでは `pyproject.toml`、lockfile、CI が示すツールと対応Python versionを優先する。

---

## 原則

### 1. 公開境界と変更コードに型を付ける

公開API、module boundary、変更する関数の引数と戻り値には型アノテーションを付ける。未型付けのlegacy code全体を、局所変更の副作用として一括修正しない。

```python
# 悪い例
def add(a, b):
    return a + b

# 良い例
def add(a: int, b: int) -> int:
    return a + b
```

### 2. `Any` は原則禁止

代替手段がない場合を除き `typing.Any` を使用しない。やむを得ない境界では範囲を狭くし、理由をコメントする。`Any` の使用と `# type: ignore` は別物なので、不正なignoreで隠さない。

- 型が本当に不明な場合は `object` を使う。
- 構造的な契約を表現する場合は `Protocol` を使う。
- 呼び出しをまたいで型情報を保持する場合は `TypeVar` / `Generic` を使う。

```python
# 悪い例
from typing import Any
def process(data: Any) -> Any: ...

# 良い例
from typing import Protocol
class Processable(Protocol):
    def process(self) -> str: ...
```

### 3. 例外の握り潰し禁止

例外を処理せずに飲み込んではならない。ログ出力も再 raise もない `except: pass` や `except Exception: pass` は禁止。

- エラーを本当に無視してよい場合は、その理由をコメントで明示する。

```python
# 悪い例
try:
    connect()
except Exception:
    pass

# 良い例
try:
    connect()
except TimeoutError:
    logger.warning("接続がタイムアウトしました。リトライします")
```

### 4. 意味を持つリテラルを定数化する

業務ルール、設定、単位、反復識別子を表すリテラルは名前付き定数にする。一度だけ使う明白な値やテスト例まで機械的に定数化しない。

```python
# 悪い例
if retries > 3:
    raise RuntimeError

# 良い例
MAX_RETRY_COUNT = 3
if retries > MAX_RETRY_COUNT:
    raise RuntimeError
```

### 5. 関数は単一責任

関数はそれぞれ 1 つのことだけを行う。説明に「〜して〜する」という複合表現が必要な場合は、分割する。

### 6. 導入済みテストフレームワークに従う

- pytestを採用している場合、テストファイルは `test_<モジュール名>.py` とする。
- テスト関数: `test_<挙動>_<条件>()`
- 期待される例外は `pytest.raises` を使用する。手動で catch して assert するのは禁止。
- 既存suiteが`unittest`の場合、規約適用だけを理由にpytestへ混在・移行しない。
