# `tests/hooks/test-approval-hooks.sh`

## 目的・役割

`hooks/auto-approve-readonly.sh`（PreToolUse hook）の shell verification。常時許可、session-approved、複合 command、write mode、destructive block、session temp、cleanup、working repo dynamic defense を positive / negative の両面から検証する。

根拠: `tests/hooks/test-approval-hooks.sh:1-40`, `docs/L3_implementation/hooks/auto_approve_readonly.md`

## 動作概要

`run_auto`（Claude Code 形式の hook payload）と `run_auto_codex_symlink`（Codex CLI symlink 経由）で `hooks/auto-approve-readonly.sh` を isolated `TMP_DIR`（`SESSION_FILE` を含む）上で直接実行し、stdout の decision JSON と `logs/auto-approve/` のログ行を `assert_json_decision` / `assert_no_output` / `assert_log_matches` で検証する。

主なカバレッジ:
- Bash allowlist の境界（Git / GitHub CLI / Unix read tools / curl / npm / journalctl / gsettings / gnome-extensions / gdbus / gresource / dpkg / tmux 等）の positive / negative ペア
- `for VAR in LIST; do ...; done` ループ（`;` 区切り・改行区切り）の read-only body の positive case と、unsafe body・C-style `for ((...))`・`$()` 経由の unsafe list・`in` 省略形の negative case（issue #224）
- `git add`/`git commit -m`/`git fetch` の narrow allow-shape（session-approved 不要で無条件承認される3パターン）の positive / negative ペア（`-A`/`--all`/`.`/`*`、`--amend`/`--no-verify`/`-a`、refspec/`+`強制指定 等は negative）
- variable expansion 除外（unquoted / double-quoted `$VAR` の smuggling）の negative case と、flag-invariant なコマンドでの positive case（`git add`/`git commit`/`git fetch` の allow-shape に対する smuggling も含む）
- `$(...)` command substitution の read-only 検証（`_extract_subshell_contents` / `_strip_subshells` / `_subshells_are_safe` 経由）
- session-approved fast path、destructive guard、working repo dynamic defense（WIP commit）
- `rm [-f] <literal-path>` の自動承認（issue #248）: working repo 内パスへの literal（変数・グロブ・複数トークンなし）な `rm`/`rm -f` の positive case（WIP commit 作成も検証）と、variable 参照・repo root 自体・`.git` 配下・複数トークン・グロブ・`-rf`（recursive、対象外）・保護対象パスを negative case として固定。現在セッションの session-approved ファイル自身への literal `rm`/`rm -f` は `is_rm_protected_path` により保護対象であり、常に negative case（issue #250。issue #248 時点では positive case だった）
- `xargs`/`find -exec`（issue #254）: read-only な wrapped command を持つ `xargs`（分離/添字形の `-I`、`-0`、`-n`/`-P`、`--` marker、パイプライン経由）と `find -exec`/`-execdir`（`\;`/`+` 終端、複数 `-exec` 節）の positive case、unsafe な wrapped command・終端記号欠落・一部の節だけ unsafe・認識対象外の xargs オプション（long option・クラスタ化）・`sh -c` のような未対応 wrapped command・変数展開による smuggling の negative case。`-fprintf` は `-exec` 系と異なりコマンドをラップしないため既存の `-delete` と同様に無条件拒否のままであることも固定

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

- e8d33b3 feat(#254): recursively validate xargs and find -exec wrapped commands in auto-approve hook
- 87ce937 fix(#250): protect session-approved from auto-approved rm, tighten task.md Step 2 checklist
- ade5abd feat(#248): add literal-path rm auto-approval and resolve-then-embed convention
- 77938cc fix(#246): mask quoted-delimiter heredoc bodies in the auto-approve hook
- 1b605dc feat(#244): recognize known-safe absolute-path invocations in the auto-approve allowlist
- 199021a feat(#236): add narrow allow-shape for gdbus introspect
- b45c722 feat(#235): add narrow allow-shape for read-only tmux subcommands
- 3a10d2c feat(#234): add narrow allow-shape for read-only gresource subcommands
- 80f5a32 feat(#233): add narrow allow-shape for read-only dpkg query subcommands
- 15877ae feat(#238): add strings/readlink/ss/apt-cache/desktop-file-validate/man/diff/sleep to the auto-approve hook's read-only tools allowlist
- d3b2129 fix(#231): add sha256sum to the auto-approve hook's read-only tools allowlist
- d5a823a feat(#224): add for/do/done allow-shape to auto-approve-readonly.sh
- 377cdd3 feat(#221): allow-shape auto-approve for local git writes, add review-resolve session gate
- 13987a8 feat(#219): add duration_ms timing to auto-approve-readonly.sh decision log
- db6d6c3 fix(#210): resolve session id from env instead of a shared pointer file
