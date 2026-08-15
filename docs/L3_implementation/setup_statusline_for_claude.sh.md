# setup_statusline_for_claude.sh

## 目的・役割

Claude Code 用 status line の実体を repository に保ったまま `~/.claude/statusline.sh` へ symlink し、Claude Code settings に command 型の `statusLine` を登録する installer である。

根拠: `setup_statusline_for_claude.sh:1-9`

## 動作の概要

- repository 内の `scripts/statusline.sh` が存在することを確認する
- 既存 target が symlink なら置換し、実ファイルなら `.bak` へ退避する
- `~/.claude/statusline.sh` を repository source への symlink として作成する
- `~/.claude/settings.json` がなければ空 JSON を作成する
- `jq` があれば、未設定の場合だけ `statusLine` command、padding、refresh interval を追加する
- `jq` がなければ手動設定例を表示する

根拠: `setup_statusline_for_claude.sh:11-57`

## 重要な設計判断

status line 本体は配布先へコピーせず symlink する。既存の実ファイルは破棄せず `.bak` に退避し、既存 `statusLine` 設定は上書きしない。

## 統合ポイント

- source: `scripts/statusline.sh`
- symlink target: `~/.claude/statusline.sh`
- config: `~/.claude/settings.json`
- manual entry point: `./setup_statusline_for_claude.sh`

## 注意事項・既知の制限

settings の自動更新には `jq` が必要である。反映には Claude Code の再起動が必要である。
