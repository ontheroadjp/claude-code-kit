# scripts/statusline.sh specification

## 目的・役割

Claude Code の statusLine コマンドとして登録されるスクリプト。stdin から渡される JSON からコンテキスト使用率と 5時間/7日レートリミットを抽出し、色付きの1行サマリを標準出力へ返す。

根拠: `scripts/statusline.sh:1-2`, `docs/L3_implementation/scripts/README.md:9`

## 動作の概要

1. stdin の JSON から `context_window.used_percentage` を取得する。存在しない場合は `current_usage` の各トークン数を合計し `bc` で概算パーセンテージを算出する
2. `rate_limits.five_hour` / `rate_limits.seven_day` の使用率と reset 時刻を取得する
3. 取得できた項目のみ `parts` 配列に追加し（コンテキスト/5h/7d）、` | ` 区切りで連結して `echo -e` で出力する

根拠: `scripts/statusline.sh:10-84`

## 統合ポイント

- セットアップ: `setup_statusline.sh` が `~/.claude/statusline.sh` へ symlink し settings に登録する（直接編集は本体の `scripts/statusline.sh` に対して行う）
- 入力: Claude Code が statusLine 呼び出し時に渡す JSON（`context_window`/`rate_limits`）

## 注意事項・既知の制限

- `date -r` (BSD/macOS) と `date -d` (GNU/Linux) の両方を `||` で試すことで reset 時刻表示の OS 差異を吸収している
- 配列インデックスのループ (`for i in "${!parts[@]}"`) で区切り文字を挿入する箇所は、ShellCheck (SC2086) の指摘に従い `[ "$i" -gt 0 ]` とダブルクオートしている（`$i` は常に数値だが、意図しない word splitting / globbing を防ぐため明示的にクオートする）

## 変更履歴（git log より自動生成）

- d4bd418 feat(#267): add /coding-sh command and enforce shellcheck across all shell scripts
- 0f5a648 fix: use current_usage for ctx pct and show n/a when unavailable
- 1986a8d fix: fallback ctx percentage calc when used_percentage is 0
- c1c36b3 fix: calculate ctx percentage from raw tokens when used_percentage is absent
- 31e84ad chore: add statusline.sh script for Claude Code status line display
