# `scripts/rename-thread.sh`

## 目的・役割

Claude Code の作業フローがブランチを切り替えた直後、現在の会話スレッド名をそのブランチ名に更新する補助スクリプト。

根拠: `scripts/rename-thread.sh:1-4`

## 動作の概要

1 個の非空引数（スレッド名）を受け取る。`CLAUDE_CODE_SESSION_ID`、現在の working directory、および `~/.claude/projects/` から transcript を導出し、既存 transcript の末尾に `custom-title` レコードを追記する。Claude Code セッション ID がない、または transcript が存在しない場合は何も変更せず正常終了する。不正な引数数または空の名前は usage を stderr に出して終了コード 2 で失敗する。

根拠: `scripts/rename-thread.sh:6-27`

## 設計判断

呼び出し元のブランチ切替・実装をタイトル更新の失敗で止めないため、`/task`・`/patch` はこのスクリプトを `|| true` で best effort として呼び出す。スクリプト自身は Claude Code の保存形式だけを操作し、Codex CLI のスレッド名を変更しない。

根拠: `commands/task.md:125-130`, `commands/patch.md:59-64`

## 統合ポイント

- 呼び出し元: `commands/task.md`、`commands/patch.md`
- 配布: `install.sh` の `scripts/*.sh` symlink により `~/.claude/scripts/rename-thread.sh` と `~/.codex/scripts/rename-thread.sh` へ配置
- テスト: `tests/scripts/test-rename-thread.sh`

## 注意事項

transcript の保存先は Claude Code のローカル実装に依存する。保存形式または配置規則が変更された場合、スクリプトは安全に no-op となるが、スレッド名は更新されない。
