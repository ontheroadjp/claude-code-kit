# test-install.sh specification

## 目的・役割

`tests/install/test-install.sh` は `install.sh` の template symlink contract と `hooks/lib/*.sh` symlink contract（issue #316）を実ユーザー環境へ副作用を与えずに検証する shell test である。

根拠: `tests/install/test-install.sh:1-19`

## 動作の概要

fixture repository と一時 HOME を作成し、fixture にコピーした installer を2回実行する。各実行後、Claude/Codex 両 template target の symlink・link target、および `hooks/lib/*.sh` の Claude/Codex 両 target への symlink を検証する。

根拠: `tests/install/test-install.sh:9-32`, `tests/install/test-install.sh:60-80`

## 主要な判定ロジック・フロー

- `assert_symlink` は link の存在と `readlink` の完全一致を確認する
- `assert_template_links` は repository 内4 template を target ごとに検証する
- `assert_hooks_lib_links` は fixture の `hooks/lib/example-lib.sh` が `~/.claude/hooks/lib/` と `~/.codex/hooks/lib/` の両方へ symlink されることを検証する（issue #316: `install.sh` に追加した `hooks/lib/*.sh` symlink ループの回帰防止）
- fresh HOME に legacy template target が作られないことを確認する
- installer 再実行後も同じ contract が成立することを確認する

根拠: `tests/install/test-install.sh:34-73`

## 重要な設計判断

installer 全体を fixture で実行することで、静的文字列検査だけでなく実際の symlink 動作と idempotence を検証する。HOME を隔離するため利用者の `~/.claude` / `~/.codex` は変更しない。

## 統合ポイント

- test target: `install.sh`
- execution: `bash tests/install/test-install.sh`
- dependencies: Bash, standard Unix tools, optional `jq` behavior inherited from installer

## 注意事項・既知の制限

- template 内容自体は検証せず、配置と symlink target の契約だけを検証する
- legacy target は削除動作ではなく、fresh HOME で新規作成されないことを検証する

## 変更履歴（git log より自動生成）

- e7d5698 fix(#316): resolve session paths via hooks/lib/session-paths.sh to survive worktree-isolated harness guard
- 27f1861 feat(#76): install templates for claude and codex
