# hooks/log-access-prompt.sh specification

## 目的・役割

UserPromptSubmit hook。ユーザーの最新プロンプトをセッション相関用に保存し、新規セッション開始時には孤立した前セッションの `PENDING_FILE` を main log へ flush する。

根拠: `hooks/log-access-prompt.sh:1-2`

## 動作の概要

1. stdin の hook payload から `session_id` / `prompt` を取り出す（`session_id` が空なら何もせず終了）
2. `SESSION_DIR/<session_id>.prompt` に最新プロンプトを保存する
3. `STATE_FILE`（`SESSION_DIR/<session_id>.json`）が存在しない場合（＝新規セッション）:
   - `SESSION_DIR` 内の孤立した `*.pending` ファイル（現在の `session_id` 以外）を月次 log へ flush し、対応する state/prompt ファイルを削除する
   - `current_phase:"work"` で始まる新しい state を初期化する

根拠: `hooks/log-access-prompt.sh:4-47`

## 統合ポイント

- 書き込み: `SESSION_DIR/<session_id>.prompt`、`SESSION_DIR/<session_id>.json`（新規セッション時）
- 消費者: `hooks/log-access-tool.sh`（同じ `STATE_FILE` を読む）、`hooks/log-access-stop.sh`
- 登録: `install.sh` が `hooks/*.sh` を symlink し、UserPromptSubmit イベントとして登録する

## 注意事項・既知の制限

- `set -euo pipefail` の下で動作する。`[ -z "$session_id" ] && exit 0` のような guard 節は、失敗した左辺のコマンドが `&&`/`||` list の一部であるため `set -e` を発火させない（bash の仕様どおり）
- 孤立 `*.pending` の flush は `_get_log_file` が repo 内 `logs/access/` を都度 `mkdir -p` して解決する
