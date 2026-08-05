# hooks/log-access-tool.sh specification

## 目的・役割

PostToolUse hook。tool アクセス順序と重複、修正したファイルを `STATE_FILE`（`hooks/log-access-prompt.sh` が初期化）に記録する。command file（`work.md`/`task.md`/`patch.md`/`docs-sync.md`/`init-docs.md`）を Read したタイミングで `current_phase` を切り替える。

根拠: `hooks/log-access-tool.sh:1-2`

## 動作の概要

1. stdin の hook payload から `session_id` / `tool_name` / `tool_input` を取り出す（いずれか空なら終了）
2. tool 種別ごとに対象パスを抽出する（Read: `file_path`、Glob: `pattern`、Grep: `path`、Edit/Write: `file_path`。対象外の tool は終了）
3. `$HOME` を `~` に正規化し（パラメータ展開 `${file_path//$HOME/\~}`）、`basename` を求める
4. `STATE_FILE` が存在しなければ終了（`log-access-prompt.sh` が UserPromptSubmit で初期化する前提）
5. `basename` が phase を切り替えるコマンドファイルなら `current_phase` を更新する。`work.md` の場合のみ「新規 `/work` 開始 かつ 前セッションの pending が残っている」を検知して flush + state リセットする分岐がある
6. Edit/Write は `modified_files`、それ以外は `accesses`（`seq` インクリメント）に追記して `STATE_FILE` に書き戻す

根拠: `hooks/log-access-tool.sh:4-85`

## 統合ポイント

- 入出力: `STATE_FILE`（`SESSION_DIR/<session_id>.json`）、`PENDING_FILE`（`work.md` 再開時の flush 元）
- 消費者: `hooks/log-access-stop.sh`
- 登録: `install.sh` が `hooks/*.sh` を symlink し、PostToolUse イベントとして登録する

## 注意事項・既知の制限

- `set -euo pipefail` を宣言している。guard 節（`[ -z "$file_path" ] && exit 0` 等）は `&&` list の一部であるため `set -e` と衝突しない
- `$HOME` の正規化は以前 `echo "$file_path" | sed "s|${HOME}|~|g"` だったが、ShellCheck (SC2001) の指摘に従いパラメータ展開 `${file_path//$HOME/\~}` に置き換えた。`$HOME` が通常のパス文字列である前提では両者は等価

## 変更履歴（git log より自動生成）

- d4bd418 feat(#267): add /coding-sh command and enforce shellcheck across all shell scripts
- 761866d fix(#81): accumulate access log state across turns per /work session
- 5b554ea fix: resolve symlink in BASH_SOURCE and move state init to UserPromptSubmit
- fca17ed feat(#67): track file access order and duplicates in access log hooks
- 3251527 feat(#48): extend phase tracking to docs-sync and init-docs commands
- c66082e feat(#48): add hooks to log file access per phase during work/task/patch execution
