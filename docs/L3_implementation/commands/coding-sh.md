# /coding-sh specification

## 目的・役割

`commands/coding-sh.md` は shell script 固有のコーディング規約を定義するスラッシュコマンド。`commands/coding-general.md` の言語非依存原則の上に、shell 固有のルール（ShellCheck 準拠、`set -euo pipefail`、quoting、パラメータ展開の優先）を重ねる。`commands/coding-py.md` と同様、他の `coding-*.md` への依存はなく `coding-general` のみを参照する。

根拠: `commands/coding-sh.md:1-3`

## 動作の概要

1. まず `commands/coding-general.md` を Read し、言語非依存の原則を適用する
2. 続けて本ファイルの shell 固有ルールを適用する:
   - shebang は `#!/bin/bash`
   - 直接実行するスクリプトは shebang 直後に `set -euo pipefail` を宣言する（source される共有ライブラリ、および理由をコメントで明示した意図的なベストエフォート hook は例外）
   - 変数展開は常にダブルクオート
   - 単純な文字列置換は `echo | sed` ではなくパラメータ展開を使う
   - ShellCheck の指摘は修正するか、誤検知の場合のみ理由付きコメントで抑制する（単発は該当行直前、ファイル全体に及ぶ誤検知は `set -euo pipefail` の直後に file-wide directive。リポジトリ全体の `.shellcheckrc` によるルール無効化は行わない）

根拠: `commands/coding-sh.md:1-92`

## 重要な設計判断

### `set -euo pipefail` の例外を明文化した理由

`hooks/lib/*.sh` は `source` される共有ライブラリであり、`set` はシェルオプションのため、ライブラリ内で設定すると呼び出し元シェルのオプションまで書き換えてしまう。この事故を防ぐため、ライブラリファイルは例外として明記した。

もう一つの例外（意図的なベストエフォート hook）は、`coding-general.md` の原則5（例外の握り潰し禁止）と整合させるため、省略する場合は必ず理由をコメントで明示することを条件にした。

### ファイル全体の ShellCheck 抑制を `.shellcheckrc` ではなく file-wide directive にした理由

`.shellcheckrc` によるルール無効化はリポジトリ全体に効き、誤検知ではない本当の指摘まで隠してしまう。ファイル単位の directive（`set -euo pipefail` 直後に配置）であれば、抑制対象を該当ファイルに閉じ込められる。実装時、`show-token-usage.sh` / `tests/hooks/test-approval-hooks.sh` / `tests/commands/test-report-review.sh` で確認したところ、file-wide directive は最初のコマンド（`set -euo pipefail` を含む）より**前**に置かないと効かない（ShellCheck の仕様）。

根拠: issue #267 実装時の shellcheck 実行結果

## 統合ポイント

- 呼び出し元: `commands/task.md` / `commands/patch.md`（ソースコード修正時、`.sh` ファイルに対して Read する）
- 対応する skill wrapper: `skills/coding-sh/SKILL.md`
- CI: `.github/workflows/shellcheck.yml` がこの規約の ShellCheck 準拠部分を機械的に強制する

## 注意事項・既知の制限

- coding-py/js/ts と異なり本ファイル自体にテストフレームワークの規定はない（このリポジトリの shell test は独自の assert 関数によるスクリプトであり、外部テストフレームワークを採用していないため）
