---
name: coding-sh
description: シェルスクリプト固有のコーディング規約（ShellCheck、set -euo pipefail、quoting 等）を coding-general の原則に重ねて適用する。ユーザーが /coding-sh を呼んだとき、または shell script のコーディング規約に従うよう求めたときに使用する。
---

# Coding Shell スキル

## Source Of Truth

`commands/coding-sh.md` が shell script コーディング規約の唯一の定義元。

## 必須動作

1. `commands/coding-general.md` を Read し、言語非依存の原則を適用する。
2. `commands/coding-sh.md` を Read し、shell script 固有のルールを重ねて適用する。
3. ソースファイルが明示的に指示しない限り、ルールを再解釈・省略・拡張しない。
4. 自分の前提とソースファイルの内容が矛盾する場合は、ソースファイルに従う。

## スコープガード

- このスキルから `commands/coding-sh.md` や `commands/coding-general.md` を編集しない。
- どちらかのファイルが見つからない・読めない場合は、復元されるまで coding-sh ワークフローを実行できない旨を報告する。
