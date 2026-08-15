# install.sh

## 目的・役割

`install.sh` はこのリポジトリの commands, hooks, scripts, skills, templates を Claude Code / Codex の実行環境へ symlinkし、Codex native status line を設定する。`jq` が利用可能な場合は Claude Code と Codex の hook 設定も登録する installer である。

このリポジトリを single source of truth とし、`~/.claude/` や `~/.codex/` 配下へ実体ファイルを複製しない。

根拠: `install.sh:1-60`

## 動作概要

1. repository root を解決する。
2. `~/.claude/commands`, `~/.codex/commands`, `~/.claude/hooks`, `~/.codex/hooks`, `~/.claude/hooks/lib`, `~/.codex/hooks/lib`, `~/.claude/scripts`, `~/.codex/scripts`, `~/.codex/skills`, `~/.claude/templates`, `~/.codex/templates` などの target directory を作成する。
3. `keybindings.json` を symlink した直後に、`global/CLAUDE.md` を `~/.claude/CLAUDE.md` と `~/.codex/AGENTS.md` の両方へ symlink する（issue #367。以前は README 記載の手動 `ln -s` に依存していた）。
4. repository 内の commands / hooks / hooks/lib / scripts / skills を対応 target へ、templates を Claude/Codex 両 target へ symlink する。`hooks/lib/*.sh` は `commands/*.md` が `bash ~/.claude/hooks/lib/session-paths.sh <mode>` のように直接実行するために symlink する（issue #316）。`scripts/*.sh` も agent 別の installed path から直接実行できるよう両 target に symlink する（issue #324）。存在しないファイルに対する glob 展開を避けるため hooks/lib の loop は `[ -e "$src" ] || continue` で空展開をスキップする。
5. `scripts/setup_statusline_for_codex.sh` を実行して `~/.codex/config.toml` の status line を設定する。
6. `jq` がない場合は JSON settings 更新をスキップして終了する。
7. `~/.claude/settings.json` と `~/.codex/hooks.json` がない場合は空 JSON として作成する。
8. migration helper でバージョン間の hook 変更を適用する。
9. idempotent な helper で hook entries を追加する。

根拠: `install.sh:3-109`, `install.sh:111-202`, issue #367

### Codex status line 設定の委譲

installer は `scripts/setup_statusline_for_codex.sh` を呼び出すだけとし、TOML の検出・追加・置換・冪等性は専用 script に委譲する。この呼び出しは `jq` availability gate より前にあるため、JSON hook settings を自動更新できない環境でも Codex status line は設定される。

根拠: `install.sh:108-109`, `install.sh:132-138`, `scripts/setup_statusline_for_codex.sh:1-93`

## 主要な判定ロジック

### symlink-only installer

installer は `ln -sf` で repository 内ファイルへの symlink を作成する。hook、command、script、template の実体は repository 側に残るため、変更は symlink 経由で反映される。template は同じ source file を `~/.claude/templates` と `~/.codex/templates` の両方へ link する。script も同じ source file を `~/.claude/scripts` と `~/.codex/scripts` の両方へ link するため、consumer repo 側に toolkit script を追跡させずに command specification から利用できる。

根拠: `install.sh:5-83`

### template の agent 別 installed path

Claude Code と Codex CLI がそれぞれ自身の設定 root 配下から template を解決できるよう、template target を分離する。旧 `~/.config/claude-code-kit/templates` は新規作成も削除もせず、既存ユーザー状態を破壊しない。

根拠: `install.sh:10-19`, `install.sh:56-63`

### jq がない場合の設定更新スキップ

hook 設定 JSON の安全な更新には `jq` を使う。`jq` が見つからない場合、symlink 作成後に warning を出して settings 更新だけをスキップする。

根拠: `install.sh:62-69`

### idempotent hook registration

`add_claude_hook` と `add_codex_hook` は、同じ command が既に対象 event に登録されている場合は追加しない。これにより installer を複数回実行しても同一 hook entry が重複しない。

根拠: `install.sh:74-120`

### migration helpers（remove_claude_hook / remove_codex_hook）

`remove_claude_hook` と `remove_codex_hook` は、event + command の組み合わせで既存 hook entry を除去する。`add_*` の前に呼んで旧エントリを削除することで、hook の意味が変わったときに idempotent な移行を実現する。

現在の migration:
- Stop イベントの `tmux-agent-status.sh 🔴` → 除去（`✅` として再登録）
- Codex の `auto-approve-readonly.sh` を `PreToolUse` から除去し、`PermissionRequest` に再登録

根拠: `install.sh:132-156`

## Hook 登録

Claude Code には `~/.claude/settings.json`、Codex には `~/.codex/hooks.json` へ hook event 構造を登録する。共有 auto-approve hook は Claude では `PreToolUse`、Codex では `PermissionRequest` に登録する。Codex の destructive-command guard は引き続き `PreToolUse` の `Bash` matcher に登録する。

`tmux-agent-status.sh` は以下の event に登録される。

- `PreToolUse`: `🔵`
- `UserPromptSubmit`: `🔵`
- `PostToolUse`: `🔵`
- `Notification`: `🔴`
- `Stop`: `✅`

`PreToolUse` / `PostToolUse` にも `🔵` を登録することで、permission/input wait 後に新しい `UserPromptSubmit` が発火しない再開経路でも、次の tool execution に合わせて実行中表示へ戻せる。

`Stop` は「Claude のターンが完了し次の入力待ち」を意味するため `✅` を使う。claude / codex プロセスが完全終了したときはアイコンを消す（プレフィックスクリア）ため、`~/.zshrc` 相当のシェル設定に shell wrapper 関数を追加する:

```bash
claude() { command claude "$@"; bash ~/.claude/hooks/tmux-agent-status.sh 2>/dev/null; }
codex()  { command codex  "$@"; bash ~/.claude/hooks/tmux-agent-status.sh 2>/dev/null; }
```

根拠: `install.sh:195-245`

## 統合ポイント

- `global/CLAUDE.md`: `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md` の symlink 元（issue #367）
- `hooks/auto-approve-readonly.sh`: safe/read-only tool approval
- `hooks/guard-destructive-cmd.sh`: destructive Bash guard
- `hooks/log-access-prompt.sh`, `hooks/log-access-tool.sh`, `hooks/log-access-stop.sh`: access logging
- `hooks/log-token-usage.sh`: token usage logging
- `hooks/cleanup-session.sh`: session approval cleanup
- `hooks/notify-slack.sh`: wait/stop notification
- `hooks/tmux-agent-status.sh`: tmux window status prefix

根拠: `install.sh:155-187`

## 注意事項・既知の制限

Codex hooks は installer が登録しただけでは信頼済みとは限らない。installer は `/hooks` で review/trust するよう案内する。

根拠: `install.sh:188`

## 変更履歴（git log より自動生成）

- a4aa210 feat(#367): automate CLAUDE.md/AGENTS.md global symlinks in install.sh
- d5359f7 #340 Approve Codex permission requests (#341)
- 4f4aab8 #324 Install the worktree linker for consumer repositories (#325)
- e7d5698 fix(#316): resolve session paths via hooks/lib/session-paths.sh to survive worktree-isolated harness guard
- 214011d fix: correct keybindings.json symlink path in install.sh
- 25a8151 fix: sync self-referential skill symlinks to .gitignore in install.sh
- bfc5f9f feat(install): add keybindings.json and symlink it during install
- 27f1861 feat(#76): install templates for claude and codex
- 15e9c5c fix(#181): remap Stop hook to ✅ and add clear mode to tmux-agent-status.sh
- 31702d1 fix(#179): map Stop hook to 🔴 and add process-exit ✅ via shell wrapper
- 612b51e fix(#154): replace tmux-agent-status emojis for better terminal visibility
- e160237 feat(#104): auto-configure settings.json hook entries in install.sh
