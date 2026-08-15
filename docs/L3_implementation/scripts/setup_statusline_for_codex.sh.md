# scripts/setup_statusline_for_codex.sh

## 目的・役割

Codex TUI の native status line を `~/.codex/config.toml` に設定する standalone かつ冪等な installer である。

根拠: `scripts/setup_statusline_for_codex.sh:1-10`

## 動作の概要

1. `~/.codex` と `config.toml` を必要に応じて作成する。
2. awk で `[tui]` table と既存の単一行・複数行 `status_line` を識別する。
3. status line を `context-used`, `used-tokens`, `five-hour-limit`, `weekly-limit` の4項目へ正規化する。
4. `[tui]` がなければ table ごと末尾へ追加し、table はあるが key がなければ次の table の直前または EOF に追加する。
5. 生成結果が既存 config と同じなら書き換えず、異なる場合だけ反映する。

根拠: `scripts/setup_statusline_for_codex.sh:6-93`

## 重要な設計判断

TOML 編集ロジックは `install.sh` に埋め込まず、この script に集約する。対象 table 以外の行と `[tui]` 内の他 key をそのまま出力することで、利用者の既存設定を維持する。config が symlink の場合は link 自体を置換せず link target へ内容を書き込む。

根拠: `scripts/setup_statusline_for_codex.sh:15-91`, `install.sh:108-109`

## 統合ポイント

- caller: `install.sh`
- standalone entry point: `./scripts/setup_statusline_for_codex.sh`
- config target: `~/.codex/config.toml`
- tests: `tests/install/test-setup-statusline-for-codex.sh`, `tests/install/test-install.sh`

## 注意事項・既知の制限

Codex は値が未取得の status item を表示時に省略する。設定反映には Codex の再起動が必要である。
