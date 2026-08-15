# test-setup-statusline-for-codex.sh

## 目的・役割

`setup_statusline_for_codex.sh` が利用者の実 HOME に副作用を与えず、Codex config を正しく冪等更新することを検証する shell test である。

根拠: `tests/install/test-setup-statusline-for-codex.sh:1-14`

## 動作の概要

- fresh HOME では `[tui]` table と4項目の `status_line` を新規作成することを検証する
- config はあるが `[tui]` がない場合、既存 root key を維持して table を追加することを検証する
- `[tui]` と複数行の旧 `status_line` がある場合、他の TUI key と後続 table を維持して4項目へ置換することを検証する
- fresh config と既存 TUI config の両方で2回目の実行後に内容が変化しないことを検証する

根拠: `tests/install/test-setup-statusline-for-codex.sh:27-122`

## 重要な設計判断

各 case は `mktemp` 配下の独立 HOME を使い、期待する TOML 全体との byte-level comparison で不要な変更や重複も検出する。

## 統合ポイント

- test target: `setup_statusline_for_codex.sh`
- execution: `bash tests/install/test-setup-statusline-for-codex.sh`
- dependencies: Bash, awk, cmp, diff

## 注意事項・既知の制限

Codex TUI の描画自体ではなく、Codex が読み込む `config.toml` の生成契約を検証する。
