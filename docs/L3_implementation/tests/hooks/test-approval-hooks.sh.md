# `tests/hooks/test-approval-hooks.sh`

## 目的・役割

`hooks/auto-approve-readonly.sh`（PreToolUse hook）の shell verification。常時許可、session-approved、複合 command、write mode、destructive block、session temp、cleanup、working repo dynamic defense を positive / negative の両面から検証する。

根拠: `tests/hooks/test-approval-hooks.sh:1-40`, `docs/L3_implementation/hooks/auto_approve_readonly.md`

## 動作概要

`run_auto`（Claude Code 形式の hook payload）と `run_auto_codex_symlink`（Codex CLI symlink 経由）で `hooks/auto-approve-readonly.sh` を isolated `TMP_DIR`（`SESSION_FILE` を含む）上で直接実行し、stdout の decision JSON と `logs/auto-approve/` のログ行を `assert_json_decision` / `assert_no_output` / `assert_log_matches` で検証する。

主なカバレッジ:
- Bash allowlist の境界（Git / GitHub CLI / Unix read tools / curl / npm / journalctl / gsettings / gnome-extensions 等）の positive / negative ペア
- variable expansion 除外（unquoted / double-quoted `$VAR` の smuggling）の negative case と、flag-invariant なコマンドでの positive case
- `$(...)` command substitution の read-only 検証（`_extract_subshell_contents` / `_strip_subshells` / `_subshells_are_safe` 経由）
- session-approved fast path、destructive guard、working repo dynamic defense（WIP commit）

根拠: `tests/hooks/test-approval-hooks.sh:22-100`, `tests/hooks/test-approval-hooks.sh:240-360`

## 重要な設計判断

`$(...)` 関連のテストは、レビューのたびに発見された個別 bypass をその発見順に regression test として追記する形で蓄積している（例: escaped `"` の誤認、depth=0 でのクォート未追跡、nested `$(...)` のクォート状態リーク、`saw_dollar` flag のリセット漏れ、ANSI-C クォートの誤認）。これは `hooks/auto-approve-readonly.sh` 側の `_find_top_level_subshell_spans` 単一 tokenizer への統一（issue #200）を経ても、tokenizer が対象とする bash 文法の各要素（クォート種別・エスケープ・ネスト）を個別に固定する回帰テストとして引き続き有効なため、統合や削除は行わない。

根拠: `tests/hooks/test-approval-hooks.sh:292-349`

## 統合ポイント

- 対象: `hooks/auto-approve-readonly.sh`, `hooks/lib/approval-safety.sh`
- 実行: `bash tests/hooks/test-approval-hooks.sh`
- `docs/.ai/repo.profile.json` の `commands.test:approval-hooks`

## 注意事項・既知の制限

isolated `TMP_DIR` 上での直接実行による静的検証であり、実際の Claude Code / Codex CLI セッションを介した end-to-end 検証ではない。`hooks/auto-approve-readonly.sh` の判定ロジックを変更した場合は、対応する positive / negative case をこのファイルに追加してから `/git-commit` すること。

## 変更履歴（git log より自動生成）

- db6d6c3 fix(#210): resolve session id from env instead of a shared pointer file
- 9f7ccdf fix(#208): close write-redirect/background-operator false positives and extend read-only allowlist in auto-approve-readonly.sh
- 4815067 fix(#200): unify subshell extraction into a single tokenizer, closing saw_dollar and ANSI-C quoting bypasses
- d3b63f5 fix(#196): track double quotes at depth=0 and save/restore quote state across nested subshells
- 40ea58a fix(#196): track single quotes at depth=0 in subshell content helpers
- ca76400 fix: add escape-awareness to subshell quote tracking in auto-approve hook
- 0ed05e5 fix(#196): fix quote-state desync when a double-quoted string contains a single quote
- 32610ca fix(#196): fix variable-expansion guard gaps found in review
- a04b853 fix(#196): close unquoted variable expansion bypass in auto-approve allowlist
- e740c91 fix(#194): replace node/bash syntax-check denylist with strict single-arg allowlist
- 3655fd5 feat(#194): extend read-only allowlist and fix multibyte log truncation
