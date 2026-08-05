# hooks/notify-slack.sh specification

## 目的・役割

任意用途の Slack 通知 helper。Notification / Stop などの hook event payload を受け取り、`CLAUDE_CODE_KIT_WAIT_NOTIFY_SLACK_WEBHOOK_URL` が設定されている場合のみ Slack incoming webhook へメッセージを POST する。

根拠: `hooks/notify-slack.sh:1-2`, `hooks/README.md:34`

## 動作の概要

1. webhook URL が未設定なら何もせず終了する
2. stdin の payload から `hook_event_name` / `cwd` / `session_id` / `message` を取り出す
3. `cwd` の末尾ディレクトリ名を `project` として抽出し、`git -C "$cwd" rev-parse --abbrev-ref HEAD` で `branch` を求める（失敗時は `unknown`）
4. イベント種別（`Notification` / `Stop` / その他）ごとに `title`/`body` を組み立て、Slack message text を `printf` でフォーマットする
5. `jq -nc` で JSON payload を組み立て、`curl` で webhook へ POST する（失敗しても `|| true` で無視し、常に `exit 0`）

根拠: `hooks/notify-slack.sh:4-45`

## 統合ポイント

- 環境変数: `CLAUDE_CODE_KIT_WAIT_NOTIFY_SLACK_WEBHOOK_URL`
- 呼び出し元: 他の hook から呼び出して使う想定（`hooks/README.md` の分類どおり、単体では特定イベントに登録されていない）

## 注意事項・既知の制限

- `set -euo pipefail` を宣言しているが、Slack 通知の失敗が hook 全体の失敗にならないよう `curl` 呼び出しは `|| true` で握り潰し、末尾で明示的に `exit 0` する
- `text=$(printf '*%s*\n%s\n...' ...)` の `printf` フォーマット文字列は意図的に単一引用符（`$` を展開させない）にしている。ShellCheck の SC2016 誤検知のため、該当行直前に `# shellcheck disable=SC2016` を付与した
