# `tests/hooks/test-approval-hooks.sh`

## 目的・役割

`hooks/auto-approve-readonly.sh` の shell verification。Claude PreToolUse と Codex PermissionRequest の常時許可、session-approved、複合 command、write mode、destructive block、session temp、cleanup、working repo dynamic defense を positive / negative の両面から検証する。

根拠: `tests/hooks/test-approval-hooks.sh:1-40`, `docs/L3_implementation/hooks/auto_approve_readonly.md`

## 動作概要

`run_auto`（Claude Code の PreToolUse payload）と `run_auto_codex_symlink`（Codex CLI の PermissionRequest payload）で `hooks/auto-approve-readonly.sh` を isolated `TMP_DIR`（`SESSION_FILE` を含む）上で直接実行する。Claude の legacy decision JSON、Codex の `hookSpecificOutput.decision.behavior: allow`、ログ行をそれぞれの assertion で検証する。

主なカバレッジ:
- Bash allowlist の境界（Git / GitHub CLI / Unix read tools / curl / npm / mise / journalctl / gsettings / gnome-extensions / gdbus / gresource / dpkg / tmux 等）の positive / negative ペア(`gh --version`・`mise current`/`ls`/`list` の positive case、`mise use`/`install`/`settings set` の negative case を含む。issue #276)
- `for VAR in LIST; do ...; done` ループ（`;` 区切り・改行区切り）の read-only body の positive case と、unsafe body・C-style `for ((...))`・`$()` 経由の unsafe list・`in` 省略形の negative case（issue #224）
- `git add`/`git commit -m`/`git fetch`/`git checkout main`・`git switch main` の narrow allow-shape（session-approved 不要で無条件承認されるパターン）の positive / negative ペア（`-A`/`--all`/`.`/`*`、`--amend`/`--no-verify`/`-a`、refspec/`+`強制指定、`main` 以外のブランチ名・`--`・`-b`/`-c`・追加トークン 等は negative。`--force`/`checkout .` は destructive guard により session 状態に関わらず block されることも固定。issue #289）
- variable expansion 除外（unquoted / double-quoted `$VAR` の smuggling）の negative case と、flag-invariant なコマンドでの positive case（`git add`/`git commit`/`git fetch` の allow-shape に対する smuggling も含む）
- `$(...)` command substitution の read-only 検証（`_extract_subshell_contents` / `_strip_subshells` / `_subshells_are_safe` 経由）
- session-approved fast path、destructive guard、working repo dynamic defense（WIP commit）
- `rm [-f] <literal-path>` の自動承認（issue #248）: working repo 内パスへの literal（変数・グロブ・複数トークンなし）な `rm`/`rm -f` の positive case（WIP commit 作成も検証）と、variable 参照・repo root 自体・`.git` 配下・複数トークン・グロブ・`-rf`（recursive、対象外）・保護対象パスを negative case として固定。現在セッションの session-approved ファイル自身への literal `rm`/`rm -f` は `is_rm_protected_path` により保護対象であり、常に negative case（issue #250。issue #248 時点では positive case だった）
- WIP squash soft reset: isolated repository で non-WIP base と WIP HEAD を作り、`git reset --soft <base hash>` だけが承認されることを確認する。HEAD target、追加 option、別 reset mode、variable target は通常許可フローへ戻ることを negative case として固定する。
- `xargs`/`find -exec`（issue #254）: read-only な wrapped command を持つ `xargs`（分離/添字形の `-I`、`-0`、`-n`/`-P`、`--` marker、パイプライン経由）と `find -exec`/`-execdir`（`\;`/`+` 終端、複数 `-exec` 節）の positive case、unsafe な wrapped command・終端記号欠落・一部の節だけ unsafe・認識対象外の xargs オプション（long option・クラスタ化）・`sh -c` のような未対応 wrapped command・変数展開による smuggling の negative case。`-fprintf` は `-exec` 系と異なりコマンドをラップしないため既存の `-delete` と同様に無条件拒否のままであることも固定
- `--explain "<command>"` 診断モード（issue #283）: `run_auto_explain` ヘルパーで argv 経由で起動し、named 関数一致（`is_safe_unix_read_tool_command`）、どの named 関数にも session-approved にも一致しない場合（session-approved ファイル不在の状態も含む）、destructive guard による block、コマンド未指定時の usage メッセージ、session-approved fast path が成立するケース、fast path は不成立だが named 関数一致と `check_session_approved` 一致の両方を1コマンド内で踏むケース（`git status && git checkout foo`）を検証。出力が PreToolUse JSON プロトコル（`{"decision": ...}`）を一切含まないことも固定
- Codex PermissionRequest: allowlisted Bash と session-temp file tool が PermissionRequest 専用 allow response を返し、legacy PreToolUse payload は neutral fallback になることを固定

根拠: `tests/hooks/test-approval-hooks.sh:22-100`, `tests/hooks/test-approval-hooks.sh:240-374`, `tests/hooks/test-approval-hooks.sh:674-680`, `tests/hooks/test-approval-hooks.sh`（`--explain` 診断モードセクション）

## 重要な設計判断

`$(...)` 関連のテストは、レビューのたびに発見された個別 bypass をその発見順に regression test として追記する形で蓄積している（例: escaped `"` の誤認、depth=0 でのクォート未追跡、nested `$(...)` のクォート状態リーク、`saw_dollar` flag のリセット漏れ、ANSI-C クォートの誤認）。これは `hooks/auto-approve-readonly.sh` 側の `_find_top_level_subshell_spans` 単一 tokenizer への統一（issue #200）を経ても、tokenizer が対象とする bash 文法の各要素（クォート種別・エスケープ・ネスト）を個別に固定する回帰テストとして引き続き有効なため、統合や削除は行わない。

根拠: `tests/hooks/test-approval-hooks.sh:292-349`

## 統合ポイント

- 対象: `hooks/auto-approve-readonly.sh`, `hooks/lib/approval-safety.sh`
- 実行: `bash tests/hooks/test-approval-hooks.sh`
- `docs/.ai/repo.profile.json` の `commands.test:approval-hooks`

## 注意事項・既知の制限

isolated `TMP_DIR` 上での直接実行による静的検証であり、実際の Claude Code / Codex CLI セッションを介した end-to-end 検証ではない。`hooks/auto-approve-readonly.sh` の判定ロジックを変更した場合は、対応する positive / negative case をこのファイルに追加してから `/git-commit` すること。

ファイル内の test fixture 文字列（例: `'for f in README.md CLAUDE.md; do ...; done'`）は意図的に単一引用符で書かれており、`$` をシェルに展開させず auto-approve hook への入力として渡している。ShellCheck SC2016 の誤検知対象のため、ファイル先頭（`set -euo pipefail` の前）に file-wide directive で抑制している（issue #267）。

## 変更履歴（git log より自動生成）

- c146ead fix(#340): approve Codex permission requests
- 880ee07 feat(#301): consolidate /new-issue draft/label/creation approval into Step 4
- a38d7ad feat(#290): accept a single branch token in git fetch <remote> allow-shape
- 16babcc feat(#289): allow bare 'git checkout main' / 'git switch main' unconditionally
- c5776f2 feat(#297): scope tool:gh_issue_write/tool:gh_pr_write session grants to issue/PR number
- 2429f81 refactor: parallelize independent run_auto loops in approval hook tests
- 5748c69 feat(#283): add --explain diagnostic mode to auto-approve-readonly.sh
- 8d684e6 fix(#280): remove 120-char truncation from auto-approve decision log
- 0685826 feat(#276): allowlist gh --version and mise current/ls/list in auto-approve hook
- d4bd418 feat(#267): add /coding-sh command and enforce shellcheck across all shell scripts
- 82b21e2 fix(#265): emit valid JSON on Codex fallback path in auto-approve-readonly.sh
- af81df0 fix(#262): remove G-0's defensive empty-write to session-approved
- f096447 feat(#258): recognize heredocs nested inside quoted $(...) in _mask_quoted_heredoc_bodies
