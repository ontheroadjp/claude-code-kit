# auto-approve-readonly hook specification

## 目的と安全境界

`hooks/auto-approve-readonly.sh` は、Claude Code では PreToolUse、Codex CLI では PermissionRequest で動く共有 hook である。通常操作の不要な許可プロンプトを減らしつつ、自動承認を次の3種類に限定する。

1. 永続状態を変更しない読み取り専用操作
2. ローカルリポジトリの外に一切影響しない narrow な git write 操作（`git add`/`git commit -m`/`git fetch`/`git checkout main`・`git switch main`。共有・remote 状態は変更しない）
3. 現在セッションでユーザーが承認したファイルまたはツールカテゴリに属する操作

この分類に確信を持てない操作は出力なしで終了し、クライアントの通常許可フローへ戻す。破壊的操作は allowlist より先に評価し、session-approved が存在しても block する。

Codex が安全な操作に対して返すのは `hookSpecificOutput.hookEventName: PermissionRequest` と `decision.behavior: allow` を含む PermissionRequest 専用レスポンスである。Codex の古い PreToolUse 呼び出しには `{}` を返し、通常の承認ポリシーへ委ねる。Claude の `{"decision":"approve"}` と空 stdout による fallback は変更しない。

根拠: `docs/L0_concept/policy.md`, `hooks/auto-approve-readonly.sh:30-31,1070-1093,1869-2074`, `hooks/lib/approval-safety.sh`

## セッションと実行元の解決

session ID の解決は `hooks/lib/session-id.sh` の `session_id_resolve` に一本化されている（`hooks/cleanup-session.sh` とも共有）。次の優先順で解決し、英数字・`.`・`_`・`-` 以外を `_` に置換する。

1. `CLAUDE_CODE_KIT_SESSION_ID`
2. `CLAUDE_CODE_SESSION_ID`（Claude Code のセッション ID。hook プロセスだけでなく、Bash tool が実行するシェルにも渡る）
3. payload の `session_id`
4. payload の `transcript_path` を hash 化した ID
5. `CODEX_THREAD_ID` を hash 化した ID
6. `process-<PPID>` fallback

承認ファイルの既定値は `${XDG_STATE_HOME:-$HOME/.local/state}/claude-code-kit/sessions/<session-id>/session-approved`、一時領域の既定値は `/tmp/claude-code-kit/<session-id>/` である。

Codex は hook の呼出しパスまたは `CODEX_MANAGED_BY_NPM`、`CODEX_MANAGED_BY_BUN`、`CODEX_CI`、`CODEX_THREAD_ID` で判定する。それ以外は Claude とする。

根拠: `hooks/auto-approve-readonly.sh:8-45`, `hooks/lib/session-id.sh`

### グローバル共有ポインタファイルの廃止（issue #210）

以前は承認ファイルの解決結果を `${STATE_ROOT}/current-session-approved-path` という**セッションでスコープされないグローバル単一ファイル**に書き出し、`commands/work.md`/`task.md`/`patch.md`/`docs-sync.md`/`git-pr.md` がそれを読んで自セッションの `SESSION_ID`/`SESSION_TMP_DIR` を逆算していた。複数セッションが同時に走ると、直近に hook を発火させたセッションがこのファイルを上書きし、他方のセッションが誤ったパスを読み取る競合が発生していた（issue #208 の作業中に別 repo の並行セッションと衝突する形で再現）。

`$CLAUDE_CODE_SESSION_ID` が hook の解決結果と完全一致することを実機で確認できたため、コマンド側は共有ファイルを経由せず環境変数から直接 `SESSION_ID` を導出するよう変更し、このポインタファイルへの書き込みは完全に削除した（読み手が存在しなくなったため）。詳細は `docs/L3_implementation/hooks/lib/session-id.sh.md` を参照。

根拠: `hooks/lib/session-id.sh:1-38`, `tests/hooks/test-approval-hooks.sh`（Concurrent-session isolation regression test）

### quoted-delimiter heredoc body のマスキング（issue #246）

`Bash` の `command` を取得した直後、`_mask_quoted_heredoc_bodies()` が `command_for_analysis`（以降の全判定が参照する解析専用の文字列）を作る。delimiter が完全にシングルクォートまたはダブルクォートされたヒアドキュメント（`<<'DELIM'` / `<<"DELIM"`。`<<-` は非対応）で、delimiter 行の残りが空白のみ、かつ本文中に delimiter と完全一致する終端行が見つかる場合に限り、演算子（`<<'DELIM'` 部分）はそのまま残しつつ、本文（複数行）と終端行を改行を含まない単一のプレースホルダー（`__HEREDOC_BODY_SAFE__`）に置換する。この形に一致しない場合（delimiter が unquoted、`<<-`、delimiter 行に他のトークンがある、終端行が見つからない等）は一切変更しない。

**なぜ安全か:** heredoc の delimiter が一部でもクォートされていると、bash はその本文に対して一切の展開（`$(...)` command substitution、backtick、`$VAR` parameter expansion）を行わない（本文はコマンドの stdin にそのまま渡される inert data）。したがってプレースホルダーへの置換によって、実行されるはずだった command substitution を隠してしまうことは原理的にありえない。演算子（`<<'DELIM'`）より前のテキスト（例: `git push --force <<'EOF'` の `--force` 部分）は置換対象に含まれず、destructive guard・write redirect 検出にそのまま渡り続ける。

これにより、`commands/git-pr.md`・`commands/new-issue.md`・`commands/triage-issues.md` が使う `gh pr create --body-file - <<'EOF' ... EOF` のような形の PR/issue 本文が、`split_shell_segments` によって改行ごとに個別の「コマンド」として分割され、read-only / session-approved のどのパターンにも一致せず毎回通常許可フローへ戻ってしまっていた問題（本文が session-approved の `tool:gh_pr_write`/`tool:gh_issue_write` で明示的に許可済みでも発生していた）を解消する。`log_decision` は判定用ではなく元の `$command`（マスキング前）を記録するため、ログには実際に実行されたコマンドがそのまま残る。

**境界検出ロジックの共有化（issue #257）:** ヒアドキュメントの境界（delimiter・終端行・resume位置）を判定する処理は `_heredoc_skip_end_index()` という単一の helper に抽出されており、`_mask_quoted_heredoc_bodies` と `_find_top_level_subshell_spans`（後述の統一 tokenizer）の両方がこれを共有する。以前は heredoc 境界検出ロジックが `_mask_quoted_heredoc_bodies` の中だけに単独実装されていたが、これは「grammar の定義箇所が複数箇所に分散し、一方だけに fix が入ってもう一方に反映されないドリフト」という、統一 tokenizer 自体が過去に解消した問題（下記「統一 tokenizer」節参照）と同じ再発リスクを抱えていたため、この issue で一本化した。

**引用符付き `$(...)` にネストされた heredoc の認識（issue #258）:** `_mask_quoted_heredoc_bodies()` は現在、`_find_top_level_subshell_spans()`（issue #257 でheredoc-aware化された統一 tokenizer）が返す top-level `$(...)` span の一覧を使い、入力を「span の外側」と「各 span の中身」に分割して処理する 2 段構成になっている。span の外側は元の単一パス走査（`_mask_quoted_heredoc_bodies_toplevel()`、旧実装そのもの）でマスクし、各 span の中身は実際の bash の挙動（`$(...)` の中は `"..."` の中であっても新しいクォート/heredoc解析コンテキストとして再開する）を反映して `_mask_quoted_heredoc_bodies()` 自身に再帰的に渡す。これにより、`git commit -m "$(cat <<'EOF' ... EOF)"` のようにダブルクォート付きの `$(...)` の中に現れる heredoc も、他の箇所と同様に本文がプレースホルダーへ置換されるようになった。置換後の形（`-m "__SUBSHELL_SAFE__"`）は commit 分岐の無条件許可パターンに元々一致するため、この形の commit は `tool:git_write` のセッション許可なしで自動承認される。

**なぜ #257 の前にはこの実装が成立しなかったか:** `_find_top_level_subshell_spans()` を生（マスク前）のテキストに対して呼ぶには、その関数自身が heredoc 本文の文字（コミットメッセージにありがちな `don't` のアポストロフィや `(#123)` の括弧等）をクォート/括弧追跡に使わずスキップできる必要がある。これを備えていない状態で2段構成を組むと、heredoc 本文の内容次第で `$(...)` の境界検出そのものが壊れる循環依存になっていた（#257 のスコープ・#200 の設計ノート参照）。#257 で `_find_top_level_subshell_spans()` 自身がheredoc-aware になったことで、この循環が解消された。

**マスキングが検証をバイパスしないことの確認:** heredoc の終端行より後、同じ `$(...)` の中に続くテキスト（例: `cat <<'EOF' ... EOF\n; rm -rf /)`）はマスク対象外のまま残り、`is_safe_segment`/`_subshells_are_safe` による通常の再帰検証を受ける。masking は heredoc 本文だけを inert data として除外するものであり、`$(...)` の中身全体を無条件許可するものではない（回帰テストで検証済み、下記「テストと既知の制限」参照）。

**引き続き未対応のまま残る形:** unquoted delimiter の heredoc（`<<EOF`）は、`$(...)` にネストされているか否かに関わらず `_heredoc_skip_end_index()` の対象外であり、既存のトップレベル挙動と同様に通常許可フローへ戻る（回帰ではなく仕様）。

根拠: `hooks/auto-approve-readonly.sh`（`_mask_quoted_heredoc_bodies`、`_mask_quoted_heredoc_bodies_toplevel`、`_heredoc_skip_end_index`、`_find_top_level_subshell_spans`、`command_for_analysis`）, issue #246, issue #257, issue #258

## 判定順序

判定は次の順序で行う。後段の allowlist は前段の block / prompt 判定を上書きしない。

0. `argv[1]` が `--explain` の場合、`payload=$(cat)` による stdin 読み取りをスキップし（`payload='{}'`）、後述の「`--explain` 診断モード」に分岐する。通常の PreToolUse stdin プロトコル（下記1以降）には一切入らない。

1. payload、session、agent、状態パスを解決する。
2. `Read` は常時承認する。
3. `Write` は session temp、承認ファイル自身、session-approved file、working repo の順に評価する。
4. `Edit` は session temp、session-approved file、working repo の順に評価する。
5. `apply_patch` は working repo 内であれば WIP commit 後に承認する。repo 外は通常許可フローへ戻す。
6. `Bash` 以外の未対応 tool は通常許可フローへ戻す。
7. `Bash` の `command` から、quoted-delimiter heredoc body をマスクした `command_for_analysis` を作る（以降の判定は全てこれを使う。ログのみ元の `command` を使う）。
8. session-approved fast path を最初に評価する（全 segment が session-approved の場合のみ即時承認）。
9. repo 内単一パスへの `rm -rf` は動的防御（WIP commit）後に承認する。
9b. `rm`/`rm -f` に literal（変数・グロブ・複数トークンなし）な単一パスが続き、それが保護対象パス（`is_rm_protected_path`。現在は session-approved ファイル自身のみ）でなく working repo 内であれば承認する（WIP commit 後）。session-approved ファイル自身への `rm`/`rm -f` は保護対象のため通常許可フローへ戻る。
10. 共有 destructive guard を評価し、該当する場合は block する。
11. `/dev/null` redirect と escaped pipe を正規化する。
12. quote-aware にファイルへの write redirect（unquoted かつ `>&` ではない `>`）を検出した場合は通常許可フローへ戻す。
13. command を quote-aware に segment 分割する（`>&<fd番号|->` は fd 複製として background operator 扱いしない）。
14. 全 segment が読み取り専用・narrow な local git write（`git add`/`git commit -m`/`git fetch`）・または session-approved のいずれかの場合のみ承認する。

### WIP squash soft reset

`/git-commit` が動的防御で作成された WIP commit を最終 commit にまとめるための `git reset --soft` は、通常の session approval を必要としない。ただし `is_wip_squash_soft_reset()` は、bare な `git reset --soft <literal 40/64桁 hash>` 以外を拒否したうえで、現在の repository の first-parent history を検査する。HEAD から連続する subject `wip:` の commit 群をたどり、その直前の non-WIP commit と target が完全に一致した場合だけ承認する。

この履歴照合により、同じ reset mode でも任意の target、non-WIP HEAD、追加 option、変数展開を含む形は allowlist に一致せず、通常の許可フローへ戻る。`--hard` は共有 destructive guard により従来どおり block される。

根拠: `hooks/auto-approve-readonly.sh:1269-1294,1627-1629`, `commands/git-commit.md:25-54`

根拠: `hooks/auto-approve-readonly.sh:806-1190`

### 実装構造: named allow-shape 関数への分割（issue #283）

`is_safe_segment`（判定順序14の実体）は、以前は約25個の匿名 inline `grep` 分岐を持つ単一の巨大関数だった。どの分岐で承認/拒否されたかを診断する手段がなく、`--explain` 診断モードを実装する前提として、各分岐を `is_safe_<name>_command`（例: `is_safe_sed_command`、`is_safe_curl_command`、`is_safe_gh_command`）という独立した named 関数に切り出した。

- 各 `is_safe_<name>_command` はコマンド名 prefix のチェックも自分自身の内部で行う自己完結した述語であり、対象外のコマンドに対しては単に `1`（非該当）を返す。
- `is_safe_segment` はこれらを `func "$seg" && return 0` という**フラットな順序非依存の列挙**として呼ぶだけのディスパッチャになった。コマンド名 prefix は互いに排他的なので、どの関数が該当するかは常に一意であり、呼び出し順序は最終結果に影響しない（ある関数が「非該当」で `1` を返しても、後続の別コマンドファミリー向け関数も prefix 不一致で `1` を返し、最終的に session-approved fast path・`return 1` へ同じように到達する）。
- `is_safe_git_read_command`・`is_safe_local_git_write_command`・`is_safe_dpkg_query_command`（`is_safe_dpkg_command` が prefix チェック付きでラップ）・`is_safe_for_in_list`・`is_safe_test_expression` は元々独立していたためロジック変更なし。
- これらの named 関数群と `is_safe_segment` 自体は、`check_session_approved` や `split_shell_segments` などと同様に、実行時に呼ばれるより前（`# Always approve Read tool` 以降のランタイム dispatch コードより前）に定義される位置へ移動した。`--explain` の実装（後述）が `payload` 未使用の早い段階でこれらの関数を呼べる必要があるための配置変更であり、判定ロジック自体への変更ではない。
- リファクタは動作を一切変えない意図で行い、`tests/hooks/test-approval-hooks.sh` の全既存アサーションが無変更のまま green であることで検証済み。

根拠: `hooks/auto-approve-readonly.sh:1236-1602`（named 関数群と `is_safe_segment` ディスパッチャ）, issue #283

## File tool の許可

### Read

`Read` は入力パスに関係なく常時承認する。

### Write / Edit / apply_patch

次の場合のみ承認する。

- 正規化後のパスが `/tmp/claude-code-kit/<session-id>/` 配下にあり、temp root と session directory が symlink ではない
- `session-approved` に `file:<absolute-path>` として列挙されている
- `Write` 対象が現在の承認ファイル自身であり、初回作成、同一内容、または既存スコープを狭める変更である
- 対象パスが working repo（Claude/Codex 起動時の PWD が属する git リポジトリ）内にある（`apply_patch` の場合は PWD がいずれかの git リポジトリ内）

承認ファイル自身へのスコープ追加は block する。working repo 内の Write / Edit / apply_patch の場合は承認前に WIP commit を作成する。その他は通常許可フローへ戻す。

根拠: `hooks/auto-approve-readonly.sh:83-115`, `hooks/auto-approve-readonly.sh:815-918`

## Bash command の許可

### 常時許可する読み取り専用操作

| 分類 | 許可内容 | 主な除外 |
|---|---|---|
| Git | `status`, `log`, `diff`, `show`, `describe`, `rev-parse`, `ls-*`, `cat-file`, `blame`, `shortlog`, `merge-base`, `stash list`, `worktree list` | `--output` |
| Git branch | 一覧・照会 mode | create/delete/move/copy/upstream変更 |
| Git remote | 一覧、`-v`, `show`, `get-url` | add/remove/rename/set-url/update |
| Git tag | 一覧・照会・verify mode | create/delete/sign/force |
| Git reflog | 一覧、`show`, `exists` | delete/expire |
| Git config | `--list`, `--get*`, `-l` | 値の設定・削除 |
| GitHub CLI | issue/PR/repository/release/run/workflow の list/view/status、`gh pr checks`、`gh auth status`、`gh api`（デフォルト GET） | write action、`gh api` の `-X/--method`, `-f/-F/--field`, `--raw-field`, `--input` |
| Shell navigation / test | `cd`, `test`, `[ ... ]`, read-only `if`, `for VAR in LIST; do ...; done`（body が read-only の場合） | command/process substitution、operatorを含む test、C-style `for ((...))`、`in` 省略の `for` |
| Unix read tools | `ls`, `cat`, `head`, `tail`, grep 系、`rg`, `fd`, `wc`, `cut`, `tr`, `sed`, `awk`, `sort`, `jq`, `yq`, `nl`, `pgrep`, `sha256sum`, `strings`, `readlink`, `ss`, `apt-cache`, `desktop-file-validate`, `man`, `diff`, `sleep` など | 下記のwrite/execute mode |
| Runtime | version 表示（`node`/`npm`/`npx`/`ruby`/`gh` の `--version`/`-v`、`python3?`/`pip3?`/`cargo`/`rustc` の `--version`/`-V`、`go version`、`bash`/`zsh --version`）、`codex --version`/`--help`/`-h`、`bash -n <file>`・`node --check`/`-c <file>`・`command -v <name>`（他のフラグを含まない単一引数形のみ） | script / program 実行、`bash -n`・`node --check`・`command -v` へのフラグ追加や複数引数（denylist ではなく「厳密な単一引数形」の allowlist。node は long option のハイフン/アンダースコア表記が等価かつ `--experimental-config-file` 経由で preload 可能なため、危険フラグの列挙では網羅できない） |
| プロセス確認 | `kill -0 <数値pid...>`（シグナル0=生存確認のみ、実際には何も送信しない） | 数値以外のpid、負のpid（プロセスグループ指定）、`-0`以外のシグナル/フラグ |
| セッション一時ディレクトリ作成 | `mkdir -p <session tmp dir またはその配下、単一パスのみ>` | `-p`以外のフラグ、複数パス、session tmp dir 外 |
| curl | default GET / HEAD 相当 | custom method、data/form、upload、config、file output |
| npm | metadata照会、config取得、引数なしの `npm run` | script実行、publish、install、audit fix等 |
| mise | 読み取り専用 introspection サブコマンド（`current`、`ls`、`list`）のみ。npm の metadata 照会と同じ positive allow-shape で、これらのサブコマンドに危険フラグが存在しないためフラグは制限しない | `use`、`install`、`settings set`、`trust` 等の書き込み系サブコマンド全般（allowlist未登録のため通常許可フローへ戻る） |
| journalctl | ログ照会全般 | `--vacuum-size/--vacuum-time/--vacuum-files`, `--rotate`, `--flush`, `--sync`, `--relinquish-var`, `--smart-relinquish-var`, `--setup-keys`, `--update-catalog`, `--force` |
| gsettings | `get`, `list-schemas`, `list-relocatable-schemas`, `list-keys`, `list-children`, `list-recursively`, `range`, `describe`, `writable` | `set`, `reset`, `reset-recursively`, `monitor` |
| gnome-extensions | `info`, `list` | `enable`, `disable`, `install`, `uninstall` 等 |
| gdbus | `introspect` | `call`（任意のD-Busメソッドを実行でき、副作用は対象メソッド依存で不明）, `emit`, `wait`, `monitor` |
| dpkg（`is_safe_dpkg_query_command`） | `-l`/`--list`, `-L`/`--listfiles`, `-s`/`--status`, `-S`/`--search` のいずれか1つのみを含む形 | `-i`/`-r`/`-P`/`--configure` 等の変更系、上記フラグを2つ以上組み合わせた形 |
| gresource | `list`, `list-sections` | `compile`（バイナリのリソースバンドルをディスクに書き出す） |
| tmux | `display-message`, `list-windows`, `list-sessions`, `list-panes`, `show-options` | `send-keys`（他のpane/sessionへの入力注入）、`kill-*`、`new-session` 等のセッション変更系 |
| Git local write（`is_safe_local_git_write_command`） | `git add <明示パス...>`、`git commit -m/--message "<message>"`（単一クォート文字列）、`git fetch` / `git fetch <remote単一トークン>` / `git fetch <remote> <branch単一トークン>`、`git checkout main` / `git switch main` | `add`: `-A`/`--all`/`.`/`*`。`commit`: `-m`/`--message` 以外の任意フラグ（`--amend`/`--no-verify`/`-a` 等）。`fetch`: refspec（`:`）、`+`強制指定、3トークン以上。`checkout`/`switch`: `main` 以外のブランチ名、追加トークン、フラグ全般（destructive guard が別途 `--force`/`checkout .` を session 状態に関わらず block する） |

`git -C <directory>` は `-C` prefix を正規化した後、同じ Git 判定を適用する。

### 絶対パス起動の認識（`normalize_absolute_path_prefix`）

`is_safe_git_read_command`・`is_safe_local_git_write_command`・Unix read tools 正規表現は、`/usr/bin/git status` のような絶対パス起動には元々一致しない（いずれも bare コマンド名にアンカーしているため）。`normalize_absolute_path_prefix` は、セグメント先頭が固定の既知安全システムディレクトリ（`/usr/bin/`, `/bin/`, `/usr/local/bin/`, `/sbin/`, `/usr/sbin/`）のいずれかで始まる場合のみ、その prefix を剥がしてから既存の allow-shape 正規表現に通す。

**なぜ「既知の固定ディレクトリ」に限定するか（issue #237 の決定）:** bare コマンド名は実行時に PATH 解決されるが、絶対パス起動は PATH を経由せず**指定パスのバイナリを直接実行**する。任意の絶対パス prefix を無条件に剥がす実装にすると、agent-writable な任意の場所（例: `/tmp/evil/git`）に置かれた偽バイナリも `git` として誤認識され、auto-approve をすり抜けてしまう。認識対象を通常環境で agent が書き込めないシステムディレクトリのみに限定することで、この迂回を構造的に防ぐ。

`is_safe_git_read_command`・`is_safe_local_git_write_command` では `normalize_absolute_path_prefix` を `normalize_git_directory_prefix` より先に適用する（`/usr/bin/git -C /tmp status` のように先頭の絶対パスを剥がして初めて `-C` prefix が認識できるため）。`_has_variable_expansion` は引き続き両正規化を適用する**前**の生 segment に対して呼ぶ（`git -C $DIR` の場合と同じ理由）。

Unix read tools 正規表現は、`cat`/`ls`/`grep` 等のようにフラグ・引数の内容に関わらず read-only が保証されるコマンド群であるため、`normalize_absolute_path_prefix` 適用に追加の variable-expansion guard は不要（bare 名invocationの既存挙動と同じ）。

根拠: `hooks/auto-approve-readonly.sh`（`normalize_absolute_path_prefix`、`is_safe_git_read_command`・`is_safe_local_git_write_command` 冒頭、Unix read tools 正規表現）, issue #237, issue #244

### `is_safe_local_git_write_command`: session-approved 不要な local git write

`git add`/`git commit`/`git fetch`/`git checkout main`・`git switch main` は `tool:git_write`（session-approved カテゴリ）にも属するが、これらのパターンに限っては**セッション同意なしで無条件承認**する専用関数 `is_safe_local_git_write_command` を `is_safe_git_read_command` の直後に追加している。

**なぜ無条件で安全か:** これらの操作はローカルリポジトリの外に一切影響しない。`add` はステージングのみ、`commit` はローカル履歴への記録のみ、許可される `fetch` の形（引数なし、remote 名のみ、または remote 名 + 単一ブランチ名）はローカルの remote-tracking ref を更新するだけで working tree・push・共有状態には触れない。`checkout main`/`switch main`（フラグなし・追加トークンなしのリテラル `main` 単独形のみ）は、git 自身が **未コミット変更を破棄するブランチ切り替えを `--force` なしでは拒否する** ため、作業内容の消失を引き起こさない（`--force` や `checkout .` は destructive guard が session 状態に関わらず block するため、この allow-shape に到達する前に排除される）。ただし、現在のブランチと `main` で内容が異なる **追跡済みファイル** は、working tree がクリーンであれば `main` の内容へ書き換わる（これは `checkout`/`switch` の通常の意味論であり、変更の「消失」ではなく、`git checkout <元のブランチ>` で常に元の状態へ戻せる）。この「未コミット変更を破棄しない」という性質は、Write/Edit tool が working repo 内のファイルを既に無条件承認している設計（動的防御セクション参照）と同じ「共有状態への影響がない」境界線上にある。

一方で `git push`・`gh issue`/`gh pr` の書き込みは GitHub 上で他者から見える共有状態を変更するため、恒久 allowlist には追加せず `tool:git_write`/`tool:gh_issue_write`/`tool:gh_pr_write`（session-approved、1セッション1回のユーザー同意）に留める。

**allowlist-shape（denylist ではない）:** `docs/L0_concept/policy.md` の設計方針に従い、いずれの分岐も「危険フラグを列挙して除外する」のではなく「安全な形だけを正規表現全体でマッチさせる」positive shape である。

- `git add`: 各トークンが `-` 始まりでなく、かつ `.`/`*` 単独でもないことを要求する。1つでも該当すれば unsafe。
- `git commit`: セグメント全体が `git commit (-m|--message) "..."` または `git commit (-m|--message) '...'` に完全一致することを要求する（`$(...)` はこのチェックより前段で `__SUBSHELL_SAFE__` に置換・再帰検証済みのため、ヒアドキュメント経由の複数行メッセージもこの形に収まる）。
- `git fetch`: `git fetch` 単体、`git fetch <remote>`、または `git fetch <remote> <branch>`（各トークンは英数字始まりの単一トークン。`--all` のような `-` 始まりトークンは除外）のみ許可する。両トークンとも同じ安全文字クラス（`[A-Za-z0-9._/-]`）を使うため、`+`強制指定や`:`区切りの destination-ref 構文は構造的に排除される。3トークン以上（例: `git fetch origin main extra`）は不一致のため `tool:git_write`（session-approved）へフォールスルーする（issue #290）。
- `git checkout main` / `git switch main`: セグメント全体が `git (checkout|switch) main`（末尾の空白のみ許容）に完全一致することを要求する。他ブランチ名、`--`、`-b`/`-c` 等の追加トークン・フラグは全て除外され、`tool:git_write`（session-approved）の従来経路にフォールスルーする。

根拠: `hooks/auto-approve-readonly.sh`（`is_safe_local_git_write_command`、`is_safe_git_read_command` 直後）, issue #221, issue #289, issue #290

### `is_safe_dpkg_query_command`: dpkg の read-only クエリ限定 allow-shape

`dpkg` は `-l`/`-L`/`-s`/`-S` のような read-only クエリと `-i`/`-r`/`-P`/`--configure` のような変更系操作を同一コマンドで混在させているため、`apt-cache`（変更系サブコマンドが一切存在しない）のように無条件では許可できない。`is_safe_dpkg_query_command` は、`-l`/`--list`・`-L`/`--listfiles`・`-s`/`--status`・`-S`/`--search` のうち**ちょうど1つ**が存在し、それ以外に `-` で始まるトークンが一切ないことを要求する。

**`git branch`/`git tag` の read-only-mode allow-shape より厳格な理由:** それらは「危険フラグを除外し、既知の read-only フラグが1つでもあれば許可」という形だが、dpkg では2つの許可フラグを組み合わせた場合（例: `dpkg -l -L pkg`）も意図的に拒否する。単一フラグのみを許可形状とすることで、フラグの組み合わせによる未検証の挙動変化を一切許容しない。

根拠: `hooks/auto-approve-readonly.sh`（`is_safe_dpkg_query_command`、`is_safe_for_in_list` 直後）, issue #233

次の mode はコマンド名が読み取り系でも常時許可しない。

- `find -delete/-fls/-fprint/-fprintf`（ファイルの削除・書き込みを直接行い、コマンドをラップしないため常に拒否。`-exec`/`-execdir`/`-ok`/`-okdir` は下記「xargs / find -exec」参照）
- `sed -i/--in-place` および script 内の `e` / `w` command
- `sort -o/--output`
- `yq -i/--inplace`
- `awk` の `system()`、外部 command を pipe する `getline`、`print`/`printf` の出力リダイレクト（`>` / `>>`）
- command を伴う `env`
- `date --set/-s`
- 値を指定する `hostname`
- `pytest`, `python -m pytest`

`curl` の短縮 option は単独形だけでなく結合形も検査する。`-so`、`-sO` のように file output や request body / upload / config を有効化する文字を含む option cluster は通常許可フローへ戻す。`-sSI` のような読み取り専用 cluster は引き続き承認する。

根拠: `hooks/auto-approve-readonly.sh:974-1175`

### write redirect 検出のクォート対応

判定順序 11 の write redirect 検出（`_has_unquoted_write_redirect`）は、`_has_variable_expansion` と同じ single/double quote + backslash escape の文法を再利用し、quote 追跡した上で unquoted な `>`（かつ直後が `&` ではないもの）だけを file-write redirect とみなす。これにより `awk -F: '$1>130 && $1<200'` のようにシングルクォート内で比較演算子として使われる `>` を誤って redirect と判定しない。

**副作用として閉じた抜け穴:** この quote-aware 化により、シングルクォート内の `>` を無条件に write redirect とみなしていた旧実装が偶発的に防いでいた `awk` 自身の `print`/`printf` 出力リダイレクト（例: `awk 'BEGIN { print 1 > "/tmp/unsafe" }'`）が、この修正だけでは auto-approve されてしまう状態が一時的に生じた。これは awk 固有 allowlist 側の `\b(print|printf)\b.*>` チェックで別途塞いでいる（上表「常時許可しない mode」参照）。`print`/`printf` キーワードの後にどこかで `>` が現れる segment は無条件に unsafe とする、意図的に粗い判定である（`print "a>b"` のような文字列リテラル内の `>` も誤検知するが、false prompt-fallback は無害であり、file write の見逃しの方が問題であるため）。

根拠: `hooks/auto-approve-readonly.sh:221-258`, `hooks/auto-approve-readonly.sh:1058-1067`

### `>&` の fd 複製認識

`split_shell_segments` の `&` ハンドラは、直前の文字が `>` かつ直後が数値 fd または `-`（境界は空白・`;`・`&`・`|`・文字列末尾）である場合、その `&` を fd 複製（`2>&1`, `1>&2`, `>&-` 等）とみなし、background operator としての分割・`__UNSUPPORTED_BACKGROUND_OPERATOR__` 付与を行わない。

**なぜ「数値 fd または `-`」に限定するか:** bash の `>&word` は word が数値または `-` の場合のみ fd 複製であり、それ以外（`>&somefile` 等）は `&>word` と同義のファイル書き込みリダイレクトである。このため判定は狭く保ち、`>&` に続く語が数値/`-` 以外の場合は引き続き background operator 分岐（結果として unsafe な `__UNSUPPORTED_BACKGROUND_OPERATOR__` segment を生成し、複合 command 全体を prompt fallback させる）に落ちる。

根拠: `hooks/auto-approve-readonly.sh:579-594`

### variable expansion の除外

`git`（`--output`・`branch`・`tag` の除外判定）、`find`、`sed`、`sort`、`yq`、`awk`、`date`、`journalctl`、`curl`、`gh api` の除外ベース判定、および `bash -n` / `node --check`・`-c` の単一引数形状判定は、segment のリテラルテキストのみを走査する。シングルクォート外に `$` 変数参照（`$VAR`/`${VAR}`）が残っている場合、`_has_variable_expansion` がこれを検出し該当 segment を unsafe と判定する。

**理由（2つの異なるハザード）:**
1. **unquoted**: bash は unquoted な変数参照を実行時に word-split（および glob 展開）するため、`ARGS='--require=./x.js target.js'; node --check $ARGS` のように前段の pure assignment segment（`_is_pure_assignment` により代入自体は安全 — 代入 RHS は word-split されないため）で危険な値を変数へ格納し、後段で unquoted 参照すると、リテラルテキスト上は「1トークン・フラグなし」に見えても実行時には複数引数・隠れフラグに展開されてしまう。
2. **double-quoted**: word-split は起きないが、展開結果はこのリテラルテキスト走査にとって不透明であり、値そのものが単一の危険フラグになり得る（例: `OUT='--output=/tmp/x'; git diff "$OUT"`）。このため double-quoted `"$VAR"` も unsafe 判定の対象とする — シングルクォートだけが例外である。

この判定は `_has_variable_expansion` を各該当ブランチの先頭で個別に呼び出す形で追加しており、`is_safe_segment` 全体を対象にした一律ブロックではない。`cat`、`ls`、`grep`/`rg`/`fd`、`head`、`tail`、`wc`、`jq` のようにフラグの有無に関わらず read-only が保証されるコマンドは対象外のままとし、変数を含んでいても引き続き auto-approve される。

`is_safe_git_read_command` では `normalize_git_directory_prefix`（`git -C <dir>` の `<dir>` operand を出力から破棄して `git <残り>` に正規化する）を適用する**前**の生の segment に対して `_has_variable_expansion` を呼ぶ。正規化後の文字列に対して呼ぶと `-C` operand に隠された変数参照（例: `DIR='repo branch -D victim'; git -C $DIR diff` — 実行時には `git -C repo branch -D victim diff` となり `git branch -D victim` が注入される）が正規化で消え、検出できなくなるため。

`$(...)` subshell は既存処理で先に検証・`__SUBSHELL_SAFE__` プレースホルダーへ置換されるため、このチェックの対象外（プレースホルダーに `$` を含まない）。`awk`/`sed` script 内の `$1` 等のフィールド参照はシングルクォートで囲まれている限り、bash が一切展開しないため対象外のまま。

**クォート追跡の詳細:** シングルクォート中は POSIX 上エスケープ機構自体が存在しない（`\` はリテラル文字）。このためシングルクォート判定はエスケープ処理より先に評価する — 逆順だと `'foo\'` のような閉じクォート直前の `\` が閉じクォートを誤って「エスケープ」したと解釈し、クォート状態がそれ以降の text（例えば後続の unquoted `$OPTS`）まで誤って持ち越されてしまう。

クォート文字自体も、それが「他方のクォートの内側ではリテラル文字である」ケースを区別する。ダブルクォート内の `'`（例: `curl --user-agent "foo'bar" $OPTS ...`）はシングルクォート開始とはみなさない — bash はダブルクォート内で `'` に特別な意味を与えないため、無条件に `quote="'"` へ遷移すると、以降の実際の閉じダブルクォートを取りこぼしてクォート状態が誤って `'` のまま持ち越され、後続の unquoted `$OPTS` を見逃す。この遷移は現在 `quote` が空（unquoted 状態）のときのみ許可する。

根拠: `hooks/auto-approve-readonly.sh:166-209`, `hooks/auto-approve-readonly.sh:606-620`, `hooks/auto-approve-readonly.sh:974-1175`

### `xargs` / `find -exec`: ラップされたコマンドの再帰検証（issue #254）

`xargs ...` と `find ... -exec/-execdir/-ok/-okdir ...` は、`$(...)` subshell と同じ「セグメント自身ではなく、引数として渡された別コマンドを実行する」構造を持つ。以前はこの構造を区別せず、`xargs` はホワイトリスト不在で default deny、`find -exec` 系は明示的な拒否対象だったため、ラップされたコマンドが `tail`/`cat` のような read-only であっても常に通常許可フローへ戻っていた。

いずれも、ラップされたコマンド部分を元のテキストから切り出し、`is_safe_segment` に再帰的に渡して判定する（`$(...)` の `_subshells_are_safe` と同じ設計）。切り出しに使う `_top_level_tokens` は、`_has_variable_expansion` などと同じ single/double quote + backslash escape の文法で、トップレベル（クォート外）の空白区切りトークンの開始・終了 index を1行ずつ出力する共有 tokenizer である。文字を再構築せず元の文字列から直接 substring を切り出すため、ラップされたコマンド自身のクォートはそのまま保持される。

#### `xargs`（`_xargs_wrapped_command`）

`xargs` 自身のオプション領域を、狭い allow-shape でのみ読み飛ばす（denylist ではない）。

| 種別 | 対象 | 値の与え方 |
|---|---|---|
| 真偽値（値なし） | `-0`, `-r`, `-t`, `-p`, `-x` | — |
| 値必須 | `-I`, `-n`, `-P`, `-L`, `-s`, `-a`, `-d` | 分離トークン（`-I {}`）または添字形（`-I{}`）の両方 |
| 値任意（添字のみ） | `-i`, `-l` | 添字形のみ（`-i{}`）。GNU xargs 自体がこれらを分離トークンの値として受け付けないため、このスキャナーも受け付けない |
| 終端 | `--` | 以降を無条件でラップされたコマンドの開始とみなす |

これら以外のトークン（GNU long option、クラスタ化された短縮フラグ `-rt`、未知のフラグ）が現れた時点で走査を打ち切り、通常許可フローへ戻す。認識したオプション領域を通過した最初の非フラグトークン以降を「ラップされたコマンド」として切り出し、`is_safe_segment` で再帰検証する。

**なぜ long option・クラスタ化を対象外にしたか:** 実際に必要になった具体例（`xargs -I{} tail -20 {}` のような log 調査パターン）は短縮オプションのみで表現できる。long option（`--replace`, `--max-args` 等）やクラスタ化（`-rt`）まで対応を広げると、オプションと値の境界判定が複雑化し誤判定のリスクが増す一方、実際の必要性が確認できていない。認識できない形は安全側（通常確認フロー）に倒れるため、必要になった時点でこの allow-shape を広げればよい。

#### `find -exec`/`-execdir`/`-ok`/`-okdir`（`_find_exec_clauses_are_safe`）

`-exec` 系の各節は、unquoted な終端記号（`\;` のようなエスケープされたセミコロン、または独立した `+` トークン）まででラップされたコマンドを構成する。`_find_exec_clauses_are_safe` は `_top_level_tokens` でトークン化した上で `-exec`/`-execdir`/`-ok`/`-okdir` トークンを見つけるたびに、終端トークンまでの範囲を元のテキストから切り出し `is_safe_segment` で再帰検証する。1つの `find` コマンドに複数の `-exec` 節がある場合は全節を検証し、1つでも unsafe なら find コマンド全体を拒否する。

**なぜ quoted terminator（`';'` 等）を対象外にしたか:** シェルの通常の書き方は `\;`（エスケープ）または `+`（unquoted）であり、`';'`/`"; "` のような quoted 形は実用上ほぼ現れない。対応を狭く保ち、認識できない形は終端記号が見つからないケースと同様に拒否（通常確認フローへ戻す）する。

**`-delete`/`-fls`/`-fprint`/`-fprintf` は対象外のまま:** これらはコマンドをラップせず、ファイルの削除・書き込みを `find` 自身が直接行うため、`-exec` 系とは異なる性質を持つ。したがって再帰検証の対象にはならず、従来通り無条件拒否を維持する。

根拠: `hooks/auto-approve-readonly.sh:592-632`（`_top_level_tokens`）, `hooks/auto-approve-readonly.sh:659-707`（`_xargs_wrapped_command`）, `hooks/auto-approve-readonly.sh:721-760`（`_find_exec_clauses_are_safe`）, `hooks/auto-approve-readonly.sh:1478-1501`（`is_safe_segment` の find/xargs 分岐）, issue #254

### session-approved tool category

`session-approved` に次の category がある場合だけ、対応する write action を承認する。

| category | 許可内容 | 除外 |
|---|---|---|
| `tool:git_write` | add, commit, merge, fetch, `pull --ff-only`, stash push/pop/apply, non-force push, branch checkout/switch, non-force branch operation | force option / `+refspec` push, pull without `--ff-only`, pull rebase/no-ff/force, checkoutによるpath復元, checkout/switch force, forced branch deletion |
| `tool:gh_issue_write:<N>` | `gh issue create`（N非依存、常時）、`gh issue (edit\|close\|delete\|comment\|reopen) <N> ...`（対象番号が grant の N と一致する場合のみ） | 対象番号が N と不一致、N が非数値の grant |
| `tool:gh_pr_write:<N>` | `gh pr create`（N非依存、常時）、`gh pr (edit\|close\|comment\|reopen\|ready\|review\|checkout\|merge) <N> ...`（対象番号が grant の N と一致する場合のみ） | 対象番号が N と不一致、N が非数値の grant、`checkout` に非数値（branch名/URL）が渡された場合 |
| `tool:gh_label_write` | `gh label create ...` | `gh label` の他 verb（edit/delete/list 等）、`gh issue`/`gh pr` の write |

destructive guard に該当する操作は category があっても block する。

根拠: `hooks/auto-approve-readonly.sh:707-748`, `hooks/lib/approval-safety.sh`

### `tool:gh_label_write`（issue #301）

`commands/new-issue.md` Step 4 が、既存ラベルに適切なものがなく新規ラベルを提案するケースで使う category。`tool:git_write` と同様、対象を特定のリソース番号にスコープしない bare category として実装した（`gh label create` はそもそも対象となる既存ラベル名を検査する必要がない操作のため、`tool:gh_issue_write:<N>`/`tool:gh_pr_write:<N>` のような numbered grant にする理由がない）。`gh issue`/`gh pr` の write action とは別の GitHub リソース（label）を対象とするため、既存の `tool:gh_issue_write`/`tool:gh_pr_write` を流用せず独立した category とした。

根拠: `hooks/auto-approve-readonly.sh:1156-1158`, `tests/hooks/test-approval-hooks.sh`（`tool:gh_label_write` の positive/negative ケース）, `commands/new-issue.md`, issue #301

### issue/PR 番号スコープ化（issue #297）

`tool:gh_issue_write`/`tool:gh_pr_write` は元々セッション全体に対する広い許可だった（対象 issue/PR 番号を一切見ずカテゴリ一致のみで承認）。`commands/triage-issues-for-hazard.md` のように untrusted な issue 本文を AI のコンテキストへ読み込んだ上で複数 issue をループ処理するフローでは、prompt injection が成功した場合に無関係な issue/PR への書き込みを誘発できる余地があった。この issue でグラント自体を対象番号にスコープし、blast radius を「そのグラントが指す番号」に縮小した。

`check_session_approved()` の `tool:gh_issue_write:*`/`tool:gh_pr_write:*` 分岐は、`category` から `:` 以降を `N` として抽出し、数字のみであることを検証する（非数値・空文字は grant として一切機能しない — fail closed）。`create` はそもそも対象となる既存番号が存在しないため（issue/PR がまだ存在しない時点で呼ばれる）、N の値に関わらず該当カテゴリの grant が1行でも存在すれば承認する。それ以外の verb（`gh issue edit/close/delete/comment/reopen <N>`、`gh pr edit/close/comment/reopen/ready/review/checkout/merge <N>`）は、コマンド中の対象番号が grant の N と完全一致する場合のみ承認する。`session-approved` に複数の numbered grant（例: `tool:gh_issue_write:42` と `tool:gh_issue_write:57`）を並べることで、複数 issue を扱うフローでも issue ごとに個別のグラントを持てる。

**`gh pr checkout` の既知の制限:** `gh pr checkout` は PR 番号だけでなく branch 名や URL も受け付けるが、この matcher は数値の対象番号のみを N と照合する。branch 名/URL を渡す呼び出しは grant があっても常に通常許可フローへ戻る（narrowing — 以前の session-scoped 広域許可では checkout 対象を一切区別していなかったため、これは意図した安全側の挙動変化である）。現在の呼び出し元（`commands/codex-review.md` の `gh pr checkout <PR番号>`）は常に数値の PR 番号のみを渡すため、実際の呼び出しパスに影響はない。

根拠: `hooks/auto-approve-readonly.sh:1094-1141`（`check_session_approved`）, `tests/hooks/test-approval-hooks.sh`（numbered grant の positive/negative ケース）, issue #297

## 複合 command

newline、`;`、`|`、`||`、`&&` を引用符の外側だけで分割し、全 segment を個別評価する。single / double quote 内の `|` は正規表現等の文字として保持する。read-onlyな `if` / `then` / `else` / `fi` / `for` / `do` / `done` は各 body を個別評価する。

### `for` / `do` / `done` ループの評価

`for VAR in LIST; do ...; done` は `if`/`then`/`else`/`fi` と同じ「制御構造キーワードは透過的に扱い、本体だけを個別に allowlist 判定する」設計で扱う。

- `for VAR in LIST` ヘッダーは `is_safe_for_in_list` が形状のみを確認して safe と判定する。このヘッダー自体はループ変数への代入を行うだけで何も実行しないため、`LIST` の内容そのものを検査する必要がない。`LIST` に含まれる `$(...)` は、この判定に到達する前に `is_safe_segment` 冒頭の再帰検証で既に safe 確認・プレースホルダー置換済みである。
- `do` は `then`/`else` と同じ prefix-strip 方式（`do` を取り除いた残りを `is_safe_segment` に再帰的に渡す）、`done` は `fi` と同じ bare keyword（本体を持たない終端）として扱う。
- ループ本体は既存の `;`/`&&`/`||`/`|` によるセグメント分割で個別セグメントに分かれるため、本体内の各コマンドは他の command と同一の read-only allowlist で判定される。`for` である無条件承認は一切ない — `for f in a b; do touch unsafe; done` のように本体が allowlist に一致しない場合は通常許可フローへ戻る。

**スコープ外（意図的にフォールスルー）:** C-style `for ((i=0;i<n;i++))` は `is_safe_for_in_list` の `in` 必須パターンに一致しないため対象外のまま通常確認へ戻る（`split_shell_segments` は算術コンテキスト内の `;` を認識せず、対応した場合ヘッダーを誤分割してしまうため）。`while`/`until`/`case`/`select`、および `in` を省略した `for VAR; do ...; done`（暗黙の `"$@"` 参照）も同様に未対応のまま。

根拠: `hooks/auto-approve-readonly.sh:486-507`, `hooks/auto-approve-readonly.sh:1047-1062`, issue #224

### `$()` subshell の評価

`is_safe_segment` は `$()` を含む segment を次の手順で評価する。

1. `_extract_subshell_contents` で各トップレベル `$(...)` の中身を抽出する
2. `_subshells_are_safe` で各中身を `is_safe_segment` に再帰的に渡し、全て read-only であることを確認する
3. 全て safe であれば `_strip_subshells` で `$(...)` を `__SUBSHELL_SAFE__` プレースホルダーに置換し、外側のコマンドをさらに評価する
4. 外側コマンドが純粋な変数代入（`VAR=value` 形式で unquoted space を含まない）であれば safe と判定する

結果として `PR_BODY=$(cat file)` や `SESSION_ID=$(basename "$(dirname "$P")")` は自動承認される。

#### 統一 tokenizer（`_find_top_level_subshell_spans`）

`_extract_subshell_contents`/`_strip_subshells` は、以前はそれぞれ独立した文字単位 state machine（かつ depth=0 用・depth>0 用に処理が二重化された実装）を持っていた。この二重化構造が、レビューのたびに一方の関数だけに bypass 修正が入り、もう一方に反映されないというドリフトを繰り返す根本原因だった。現在は両関数とも `_find_top_level_subshell_spans` という単一の tokenizer 関数の薄いラッパーであり、grammar の定義箇所は 1 箇所のみになっている。

`_find_top_level_subshell_spans` は入力全体を 1 パスで走査し、bash の実際の quoting/escaping 文法をそのままモデル化する:

- シングルクォート（`'...'`）: エスケープ機構自体が存在しない。他のどのチェックよりも先に判定する（閉じクォート直前の `\` を誤ってエスケープと解釈するのを防ぐため）。
- バックスラッシュエスケープ: ダブルクォート・ANSI-C クォート・unquoted テキストで共通の汎用処理。実際の bash のダブルクォートエスケープ対象（`\$`, `` \` ``, `\"`, `\\`）はこの「次の1文字を無条件にエスケープする」というルールの部分集合であり、このチェック対象外の文字（`$ ' " ( )` 以外）に広げても quote/paren 追跡の状態遷移には影響しないため、安全な単純化として扱う。
- ANSI-C クォート（`$'...'`）: エスケープは適用されるが、`"..."` と異なり `$(...)` や入れ子クォートは認識しない（実際の bash と同じ）。次の unescaped `'` で閉じる。`$'` は現在のネストレベルで quote が空のときのみ認識する（`"..."` や `'...'` の中では特別な意味を持たない）。
- `$(...)`: `"..."` の中でも認識する（実際の bash の挙動）。トップレベル（depth 0→1）で開始時に span の開始位置を記録し、ネストする場合は enclosing level の quote 状態を `quote_stack`（配列、`${#arr[@]}` ベースの index で push/pop）へ退避してからネストレベルを独立した quote="" で開始する。

トップレベル `$(...)` の開始・終了 index のペアを1行ずつ出力し、`_extract_subshell_contents` はそのインデックスで直接 substring を切り出し、`_strip_subshells` はそのインデックスの範囲を `__SUBSHELL_SAFE__` に置換する。いずれも文字単位の再構築（`current+=char` 相当の蓄積）を行わない。

統一 tokenizer は、単に depth=0/depth>0 の重複を消したこと自体が bypass を閉じたわけではない。旧実装では depth>0 のエスケープ消費パス（`escaped==1` 分岐・`char=='\\'` 分岐）が `saw_dollar` look-ahead flag をリセットしておらず（`saw_dollar` は depth=0 側の分岐でのみリセットされていた）、`cat $(printf "$\"(" $(touch /tmp/unsafe))` のようにエスケープされた `"` を挟んだ直後の `(` がネストした `$(` の開始と誤認され、depth が 2 のまま最後まで 0 に戻らなかった（実測で確認済み）。depth が 0 に戻らないと `_extract_subshell_contents`（旧実装）は1行も出力せず、`_subshells_are_safe` は検証対象がないまま vacuous に safe を返し、`_strip_subshells`（旧実装）も desync した時点以降の文字を `result` に一切追加しないため、外側コマンドは `cat __SUBSHELL_SAFE__` のように縮退し、本物の `touch /tmp/unsafe` が auto-approve をすり抜けていた。統一 tokenizer にはそもそも `saw_dollar` に相当する状態がなく、`$` の直後の文字を `${input:i+1:1}` で直接参照して判定するため、この種の状態リークが構造的に発生せず、depth は正しく 0 まで戻り、ネストした `$(touch ...)` は top-level span の内容に正しく含まれた状態で `_subshells_are_safe` に渡され、再帰評価で unsafe と判定される。

ANSI-C クォート（`$'...'`）はこの再設計で新たに追加した認識であり、以前は `$'...'` が単なる `'...'` として扱われ、その中の `\'`（ANSI-C クォート内では実際にエスケープされた `'` だが、通常のシングルクォートには存在しない）が閉じクォートと誤認され、以降の本物の `$(...)` が誤ったクォート状態の下で見過ごされていた。統一 tokenizer は `$'` を独立したクォート種別として認識し、エスケープを適用しつつ `$(...)` や入れ子クォートを認識しないという ANSI-C 固有の規則を正しく適用する。

`_find_top_level_subshell_spans` は depth が 0 に戻った時点でのみ span を出力するため、万一まだ未知のクォート/エスケープ相互作用で depth desync が再発した場合も、誤った境界の内容を出力するのではなく該当 span を出力しないという性質は変わらない。ただしこれは今回の2件の bypass を閉じる直接の修正ではなく、`_subshells_are_safe` が抽出0件のまま vacuous に safe を返す既存の弱点（issue #200 で defense-in-depth backstop 案として言及）自体を解消するものではない — 今回のスコープでは2件の既知 bypass の解消と回帰テストの追加に限定し、backstop の追加は見送った。

#### heredoc 本体のスキップ（issue #257）

`_find_top_level_subshell_spans` は、`quote==""`（現在のネストレベルで未クォート）の位置に `_heredoc_skip_end_index()` が認識するヒアドキュメント（`_mask_quoted_heredoc_bodies` と同じ narrow な形状: `<<'DELIM'`/`<<"DELIM"`、`<<-` 非対応）が現れた場合、その本文と終端行の文字を一切クォート/括弧追跡に使わずスキップするようになった。

**なぜ必要か:** ヒアドキュメント本文は inert data であり、コミットメッセージや PR 本文にありがちな `don't` のようなアポストロフィや `(#123)` のような括弧を自由に含みうる。もしこの関数がそれらの文字を通常のクォート/括弧として追跡してしまうと、本文の内容次第で `$(...)` の終端位置検出そのものが破綻しうる。

**なぜ `_mask_quoted_heredoc_bodies` を先に呼ぶのではなく同一パスに統合したか:** `_mask_quoted_heredoc_bodies` を前処理として先に呼び、その結果に対して `_find_top_level_subshell_spans` を呼ぶ、という2パス構成は循環依存になり成立しない。`_mask_quoted_heredoc_bodies` 自身がダブルクォート内の `$(...)` に現れる heredoc を認識するには `$(...)` のネスト境界（`_find_top_level_subshell_spans` が提供する情報）が必要であり、かつ `_find_top_level_subshell_spans` を生テキスト（heredoc本体マスク前）に対して呼ぶと、本文中の未対応クォート・括弧文字がその関数自身の追跡を破壊しうる。この issue はこの循環を解く前段として、まず `_find_top_level_subshell_spans` 単体を heredoc-aware にする（本体を持つ限り、常に単一パスでその本体をスキップできる）リファクタリングのみを行う。

**この issue 単体での到達可能性:** 現在の呼び出し経路（`command_for_analysis = _mask_quoted_heredoc_bodies(command)` が最初に走り、`_find_top_level_subshell_spans` はそれ以降の判定でのみ呼ばれる）では、この関数が生の（マスク前の）ヒアドキュメント本体を受け取ることは無い。したがってこの変更はこの issue の時点では外部から観測可能な挙動を一切変えない（`tests/hooks/test-approval-hooks.sh` の全既存アサーションが無変更のまま green であることで検証済み）。ダブルクォート付き `$(...)` に nest した heredoc（`git commit -m "$(cat <<'EOF' ... EOF)"`）を実際に認識・マスクできるようにする変更は issue #258 で行う。

根拠: `hooks/auto-approve-readonly.sh`（`_find_top_level_subshell_spans`、`_heredoc_skip_end_index`）, issue #200, issue #257

### 常時ブロックする構文

次は安全に分類せず通常許可フローへ戻す。

- 単独の background operator `&`
- backtick `` ` `` による command substitution（常時ブロック）
- process substitution `<()` / `>()`（常時ブロック）
- `$()` の中身に unsafe なコマンドが 1 つでも含まれる場合
- 未対応のshell構文
- 1つでも未許可のsegmentを含む複合command

根拠: `hooks/auto-approve-readonly.sh:144-147`, `hooks/auto-approve-readonly.sh:274-445`, `hooks/auto-approve-readonly.sh:650-704`, `hooks/auto-approve-readonly.sh:1180-1190`

## decision とログ

| 結果 | Claude PreToolUse | Codex PermissionRequest |
|---|---|---|
| approve | `{"decision":"approve"}` | `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}` |
| prompt fallback | stdoutなし | `{}` |
| destructive block | reason付きblock JSON | reason付きblock JSON |

**prompt fallback が Claude と Codex で異なる理由:** Claude Code は stdout が空の場合「hook は判定しない」と解釈し、通常の許可フローへ委ねる。Codex では `{}` を返し、PermissionRequest の通常承認フローへ委ねる。`emit_fallback()` は Codex invocation の場合のみ `{}` を出力するため、Claude 側の挙動は変更しない。

根拠: `hooks/auto-approve-readonly.sh`（`emit_fallback`）, issue #265

decision log は `logs/auto-approve/YYYY-MM.log` に次の形式で追記する。process fallback の session は `n/a` とする。

```text
[timestamp] agent=claude|codex session=<id|n/a> result=<result> tool=<tool> duration_ms=<ms|NA> <detail>
```

`duration_ms` はスクリプト冒頭（`payload=$(cat)` の前）で取得した `$EPOCHREALTIME`（bash 5.0+ のビルトイン変数、サブプロセスなし）を起点に、`log_decision()` 呼び出し時点までの経過ミリ秒を純粋な bash 整数演算（`10#` prefix で usec の leading zero を octal 誤解釈しないようにする）で計算したものである。`$EPOCHREALTIME` が使えない bash（5.0未満。例: macOS デフォルトの `/bin/bash` 3.2）では `duration_ms=NA` とし、計測不能を正直に記録する（サブプロセスベースの代替計測は行わない）。`scripts/analyze_auto_approve.py` の `LINE_RE` はこのフィールドを任意グループとして扱うため、`duration_ms` を持たない旧フォーマットのログ行も引き続き解析できる。集計・レポートへの反映は issue #218 のスコープ。

`detail` は改行をスペースに正規化するのみで、以前あった120文字への切り詰め（`cut -c1-120` + `truncate_utf8_safe()` によるマルチバイト境界の UTF-8 安全化）は撤廃した（issue #280）。`log_decision` はマスキング前の元 `$command` を全文記録する。

根拠: `hooks/auto-approve-readonly.sh:64-73`, `hooks/auto-approve-readonly.sh:1026-1035`

## `--explain` 診断モード（issue #283）

### 目的

`hooks/auto-approve-readonly.sh --explain "<command>"` は、あるコマンドが自動承認されない理由（またはされる理由）を、ログを手で読まずに調べるためのデバッグ専用エントリポイントである。`logs/auto-approve/*.log` に蓄積される `user_prompt` 行を allowlist 拡張の判断材料にする一連の取り組み（issue #278, #280, #282）の一部で、これまでは `is_safe_segment` の約25分岐のソースを直接読む以外に手段がなかった。

### 到達経路と安全性

- `argv[1]` が `--explain` の場合のみ到達する。通常の Claude/Codex hook 呼び出しは stdin 経由の JSON payload で呼ばれ、`--explain` という引数を渡すことはないため、実運用の PreToolUse 判定には一切影響しない。
- 検出は `payload=$(cat)` より前で行う（`EXPLAIN_MODE`/`EXPLAIN_COMMAND` を設定し、stdin を読まず `payload='{}'` を使う）。これにより、ターミナルから対話的に実行した際に stdin 待ちでブロックしない。
- `run_explain`/`_explain_segment` の実装は `check_session_approved`・`is_safe_<name>_command` 群・`split_shell_segments`・`_mask_quoted_heredoc_bodies`・`approval_safety_destructive_reason` など、実際の決定パスと**同じ関数**を呼ぶ。判定ロジックを別実装として複製していないため、`--explain` の出力と実際の decision は構造的に乖離しない。
- 副作用なし: `do_wip_commit` を呼ばない、`SESSION_APPROVED_FILE` への書き込みを行わない、`log_decision` を呼ばない（decision log には記録されない）。`SESSION_APPROVED_FILE` の**読み取り**のみ行う（現在のセッションの session-approved 状態を反映したレポートを出すため）。

### レポート内容

実際の Bash 判定パス（判定順序7〜14）と同じ順序で、以下を報告する。

1. `command_for_analysis`（heredoc body マスキング後。変化がある場合のみ表示）
2. session-approved fast path（全 segment が session-approved category に一致する場合、ここで `approve` として打ち切り）
3. `rm -rf`/`rm -f` の working repo 動的防御（該当すれば `approve` として打ち切り）
4. destructive guard（該当すれば `block` として打ち切り）
5. write redirect 検出（該当すれば `user_prompt` として打ち切り）
6. `split_shell_segments` によるセグメント分割、各セグメントについて `_explain_segment` が以下を報告:
    - `$(...)` subshell の有無と安全性
    - pure assignment / 制御構造キーワード / if・for ヘッダー / bare test expression のいずれかに該当するか
    - 該当すれば、`_EXPLAIN_CHECK_FUNCS`（`is_safe_segment` がディスパッチする named 関数と同じ一覧）のうちどれが一致したか
    - どれも一致しない場合: session-approved ファイルの有無・列挙されている category・`check_session_approved` の結果
7. 最終 verdict（`approve`/`block`/`user_prompt`）

### 既知の制限

`check_session_approved` の3 category（`tool:git_write`/`tool:gh_issue_write`/`tool:gh_pr_write`）は named 関数として個別に切り出していないため、`_explain_segment` はこの3つを1つのブラックボックス呼び出しとして扱う。3 category のうちどれが一致したか（例: `git checkout` が `tool:git_write` の checkout/switch 条件で一致したのか、fetch 条件でか）までは分解して報告しない。issue #283 の Scope で検討された (A)/(B) の判断のうち、`is_safe_segment` 側は (A)（named 関数化）を採用したが、`check_session_approved` 側は変更していない（実データ上、この3 category 自体は既に判別できているため優先度が低いと判断）。

根拠: `hooks/auto-approve-readonly.sh`（`EXPLAIN_MODE`, `run_explain`, `_explain_segment`, `_EXPLAIN_CHECK_FUNCS`）, `tests/hooks/test-approval-hooks.sh`（`run_auto_explain` 以降）, issue #283

## 動的防御（Working Repo Dynamic Defense）

### コンセプト

操作対象が working repo（Claude/Codex 起動時の `PWD` が属する git リポジトリ）内であれば、**実行前に WIP commit** を作成して自動承認する。WIP commit は `git add -A && git commit --no-verify -m "wip: <timestamp> before <detail>"` の形式で作成する。何か問題が生じた場合は `git reflog` または `git log` で WIP commit まで巻き戻すことができる。

この動的防御は既存の静的防御（`approval_safety.sh` による destructive block）の **前段** に位置する。ただし、以下は動的防御の対象外とし静的防御に委ねる。

- `git push --force` / `git filter-branch` / `git reset --hard` 等（approval_safety.sh でブロック）
- `rm -rf <repo root>` または `rm -rf <repo root>/.git` 配下（safety net 自体の破壊を防ぐ）
- 複数パスや変数を含む `rm -rf`（パスの特定が不確実）

### WIP commit の詳細

| 条件 | 挙動 |
|---|---|
| working tree が clean | WIP commit は作成しない（承認のみ） |
| working tree が dirty | `git add -A` でステージングし commit |

WIP commit が積み上がった場合、`commands/git-commit.md` は HEAD の message が `wip:` で始まるときだけ、HEAD から遡って最初の non-WIP commit を特定し、その commit へ soft reset する。これにより直近で連続する WIP commits だけを staged changes に戻し、それ以前の non-WIP commits は変更しない。

この自動 squash は hook と `commands/git-commit.md` がそれぞれの責務を担う。hook は書き込み前の復旧点を作り、git-commit workflow は commit 直前に連続 WIP だけを正規化する。

根拠: `commands/git-commit.md:25-45`

### 判定フロー

**Write / Edit:**

```
After:
  session-tmp         → approve
  session-approved-file → approve / block
  [NEW] file_path が repo 内 → WIP commit → approve
  user_prompt
```

**apply_patch:**

```
After:
  [NEW] PWD が repo 内 → WIP commit → approve
  user_prompt
```

**Bash:**

```
After:
  [NEW] 全 segment が session-approved → approve  ← 先頭に移動（fast path）
  [NEW] rm -rf + repo 内単一パス → WIP commit → approve
  [NEW] rm[-f] + literal単一パス（保護対象でなく repo内） → approve（WIP commit後）。session-approved file 自身は保護対象のため対象外
  approval_safety → block
  正規化・write redirect → user_prompt
  segment allowlist → approve
  user_prompt
```

根拠: `hooks/auto-approve-readonly.sh:815-1190`

### `rm [-f] <literal-path>` の自動承認（issue #248）と保護対象パス（issue #250）

`is_rm_f_on_safe_literal_path()` は `is_rm_rf_on_working_repo_path()` の姉妹関数であり、次の点が異なる。

- 対象は `-rf`/`-fr`（recursive+force）ではなく、`rm` 単体または `rm -f` のみ（非再帰）。
- 承認先は working repo 内パスのみ（WIP commit 後）。

**なぜ hook は変数を解決せずに安全と判定できるか:** この関数は他の allowlist 判定と同じく、コマンドの**テキスト**だけを見て判定し、一切実行しない。危険操作の対象が実行時変数に依存する場合、hook 側でその値を検証する手段はないため、エージェント側が「read-only な解決ステップ（例: `echo "$SESSION_APPROVED"`）→ 解決済みの値をリテラルとして次のコマンドに埋め込む」という2段階（resolve-then-embed）に分けることを運用規約とする（`CLAUDE.md` の「リポジトリへの操作ルール」節）。hook が見るのは変数を含まない最終的なリテラルテキストだけであり、それを `is_rm_protected_path`/`is_in_working_repo` という既存の（hook が独立に再計算する）述語と照合する。

**拒否パターン:** `is_rm_rf_on_working_repo_path` と同じ denylist（空白・`$`・`;`・`|`・`&`・`>`・`<`・バッククォート・`*`・`?`・クォート文字・`-`始まりの2番目のトークン）に加え、repo root 自体と `.git` 配下は working-repo 分岐から除外する（safety net 自体の破壊を防ぐ、`is_rm_rf_on_working_repo_path` と同じ理由）。`-rf`（recursive）はこの関数の対象外のまま既存の `is_rm_rf_on_working_repo_path` に委ねる。

**`is_rm_protected_path()`（issue #250）:** issue #248 の初期実装は working repo 内パスに加え、`is_session_approved_path()` による現在セッションの session-approved ファイル自身も無条件承認対象に含めていた。これは `commands/work.md` G-0 の Write ベースの回避策（Bash `rm -f "$SESSION_APPROVED"` が確認プロンプトに落ちる問題）に対する、hook 側の汎用的な解決策として導入されたものだった。

しかしこの2つの安全性の根拠は同一ではない。working repo 内パスが安全なのは WIP commit で復元可能だからであり、session-approved ファイルは repo 外にあり、この根拠が成立しない。session-approved は Write ハンドラのスコープ拡張ガード（判定順序3、`session-approved scope expansion blocked`）の状態そのものであり、これを無確認で削除できると、`rm -f` → 空ファイルへの「初回書き込み」として再作成、という手順でガードを回避し、ユーザーに一切提示していないスコープを無断で確定できてしまう（issue #250 で実際に観測: 一度は無確認のまま、一度は正規の追加確認と無許可の既存分の持ち越しが混在する形で発生）。issue #248 導入前はこの `rm -f` は常に通常の確認プロンプトに落ちており、それで問題なく機能していた（session-approved に含まれない操作のたびに確認が必要という不便さはあった）。

`is_rm_protected_path()` は `is_rm_f_on_safe_literal_path()` の先頭で評価する明示的な拒否リストであり、session-approved ファイル自身を保護対象として切り出す。これにより working repo 内の rm 自動承認（issue #248 の本来の目的）はそのまま維持しつつ、session-approved への `rm` は issue #248 以前の挙動（常に人間の実確認が必須）に戻る。将来的に同種の per-session 状態ファイルを追加する場合は、`is_rm_f_on_safe_literal_path()` 内に個別分岐を増やすのではなく、この関数に追加すること。

根拠: `hooks/auto-approve-readonly.sh`（`is_rm_f_on_safe_literal_path`, `is_rm_protected_path`）, issue #248, issue #250

### session-approved fast path の安全性根拠

Bash ハンドラーの先頭で「全 segment が session-approved category に一致する場合は即時承認」する fast path を設けている（判定順序 7）。`approval_safety.sh` より前に評価されるため、一見すると危険に思えるが、これが安全な理由は **session category の定義自体が dangerous ops を除外しているから**である。

具体的には:
- `git push --force` / `--force-with-lease` / `+refspec` は `tool:git_write` の `push` 判定から除外
- `git pull --rebase` / `--no-ff` は `tool:git_write` の `pull` 判定から除外
- `git checkout` / `git switch` の `-f` / `--force` は `tool:git_write` から除外
- `git branch -D`、`--delete --force`、`-df` は `tool:git_write` から除外
- `git reset --hard` / `git clean` / `git stash drop` 等は session category に一切含まれない

これらは必ず fast path を**通過できず**、approval_safety.sh での評価に落ちてブロックされる。fast path は「session-approved の操作を繰り返す際の遅延を減らす最適化」であり、安全境界を変えるものではない。

### do_wip_commit 失敗時の挙動

`do_wip_commit` は `|| true` で呼び出されるため、git コマンドが失敗しても承認を続行する。これは意図的な設計判断である。

**なぜそうしたか:** WIP commit はベストエフォートの safety net であり、失敗してもその後の操作（Write/Edit/apply_patch/rm -rf）を止める理由にはならない。WIP commit が作れない状況（git 未初期化、ディスク満杯等）でも作業を継続できることを優先した。万一の場合は `git reflog` による復旧が困難になるが、操作自体をブロックするよりトレードオフとして許容できる。

## テストと既知の制限

`tests/hooks/test-approval-hooks.sh` は常時許可、session-approved、複合command、write mode、destructive block、session temp、cleanup、working repo dynamic defense をpositive / negativeの両面から検証する。Bash allowlist の境界では、通常の `sed -e`、plain `awk getline`、read-only curl option cluster、non-force Git 操作、`git merge-base`、`pgrep`、`gh api`（GET-only）、`gsettings get`系、`journalctl`、`gnome-extensions info/list`、`bash -n`、`node --check`/`-c`、`gh --version`、`mise current`/`ls`/`list` を positive case とし、`sed e/w`、pipe-based `awk getline`、file output を含む curl cluster、Git force variants、`git merge-base --output`、`gsettings set/reset`、`journalctl --vacuum-*/--rotate/--flush/--update-catalog/--smart-relinquish-var`、`gh api -X/-XPOST/-f/-fkey=value/--input`（区切り文字なしの結合形も含む）、`gnome-extensions enable/disable`、`bash -n` へのフラグ追加・複数引数、`node --check` へのフラグ追加・複数引数（アンダースコア表記や `--experimental-config-file` 経由の preload を含む）、`mise use`/`install`/`settings set` 等の書き込み系サブコマンドを negative case として固定する（issue #276）。`for`/`do`/`done`（issue #224）については、read-only body を持つ `for VAR in LIST; do ...; done`（`;` 区切り・改行区切りの両方）を positive case、unsafe body を持つ for ループ、C-style `for ((i=0;i<n;i++))`、`$()` 経由で unsafe コマンドを list に埋め込む for ループ、`in` を省略した `for VAR; do ...; done` を negative case として固定する。

variable expansion の除外については、`node --check $ARGS` 型の報告された bypass に加え、`bash -n`・`curl`・`gh api`・`git diff --output`・`sed`・`find`・`sort`・`date`・`journalctl`・`yq`・`awk` への同型 bypass を negative case として固定し、`cat $FILE`・`grep ... $FILE`・シングルクォート awk script 内の `$1` が引き続き auto-approve されることを positive case で固定する。加えて、`git -C $DIR` operand への変数隠蔽、double-quoted 変数の単一フラグ密輸、シングルクォート内バックスラッシュの誤エスケープ、ダブルクォート文字列内のシングルクォートによるクォート状態誤遷移、`_extract_subshell_contents`/`_strip_subshells` のエスケープ未対応（escaped `"` をクォート終了と誤認し後続の変数参照が silently drop される）、同2関数が depth=0 でシングルクォートを追跡しないため single-quoted literal 内の `$(` を実際の subshell 開始と誤認する問題（例: `curl '$(' $OPTS ...`）、同2関数が depth=0 でダブルクォートを追跡しないため double-quoted 文字列内のリテラルな `'` により後続の本物の `$(` を検出し損ねる問題（例: `cat "foo'$(touch ...)"`）、およびネストした `$(...)` でクォート状態を push/pop しないため外側の double-quoted 文字列の中の nested substitution が正しく閉じられない問題（例: `X=$(printf '%s' "$(touch ...)")`）という、レビューで発見された8件の追加 bypass を negative case として固定する。統一 tokenizer への再設計（issue #200）に伴い、`saw_dollar` look-ahead flag がエスケープ消費時にリセットされず depth が 0 に戻らなくなる問題（例: `cat $(printf "$\"(" $(touch /tmp/unsafe))`）と、ANSI-C クォート（`$'...'`）が通常の `'...'` として扱われエスケープされた `\'` を閉じクォートと誤認する問題（例: `cat $'foo\'bar'$(touch /tmp/unsafe)`）の2件を追加の negative case として固定する。

issue #208 で修正した quote-unaware write-redirect 誤検知と `>&` fd 複製誤判定については、`awk -F: '$1>130 && $1<200'` のようなシングルクォート内比較演算子と `cat ... 2>&1` / `cat ... 1>&2` を positive case、`awk 'BEGIN { print 1 > "/tmp/unsafe" }'` のような awk 自身の出力リダイレクトと `cmd >&somefile`（fd 複製ではなく実ファイル書き込み）を negative case として固定する。同時に追加した allowlist（`command -v <name>`、`codex --version`/`--help`、`kill -0 <数値pid...>`、session tmp dir 配下限定の `mkdir -p`）についても、それぞれ許可される最小形を positive case、スコープ外の形（複数引数の `command -v`、`codex` の他サブコマンド、`-0` 以外のシグナルや負のpid/プロセスグループ指定を伴う `kill`、`-p` なし・複数パス・session tmp dir 外を対象とする `mkdir`）を negative case として固定する。

`is_rm_f_on_safe_literal_path`（issue #248）については、working repo 内 literal パスへの `rm -f`（WIP commit あり）を positive case、repo root 自体・`.git` 配下・変数参照・複数トークン・グロブ・`-rf`（recursive、この関数の対象外）・repo 内でない任意パスを negative case として固定する。`is_rm_protected_path`（issue #250）については、session-approved ファイル自身への literal `rm`/`rm -f` が自動承認されず通常許可フローへ戻ることを negative case として固定する（issue #248 時点では positive case だったものを、保護対象パスの導入に伴い反転）。

`xargs`/`find -exec`（issue #254）については、read-only な wrapped command を持つ `xargs`（分離/添字形の `-I`、`-0`、`-n`/`-P` の組み合わせ、`--` marker、パイプライン経由）と `find -exec`/`-execdir`（`\;`/`+` 終端、複数 `-exec` 節）を positive case、unsafe な wrapped command（`rm` 系）、終端記号の欠落、一部の節だけ unsafe な複数 `-exec`、認識対象外の xargs オプション（long option・クラスタ化）、`is_safe_segment` が元々認識しない wrapped command（`sh -c ...`）、変数展開によるオプション/wrapped command の smuggling を negative case として固定する。`-fprintf` は `-exec` 系と異なりコマンドをラップしないため、既存の `-delete` と同様に無条件拒否のまま negative case として固定する。

`log_decision` については、日本語などマルチバイト文字を含む Bash コマンドのログ行が valid UTF-8・`grep -qE` で検出可能・かつコマンド全文を保持していることを検証する回帰テストを持つ（truncate 撤廃前は120文字境界を跨ぐマルチバイト分割の UTF-8 安全性検証だったが、issue #280 で truncate 自体がなくなったため全文保持の検証に置き換えた）。

heredoc body のマスキング（issue #246）については、`gh pr create --body-file - <<'EOF' ... EOF` 形（複数行 Markdown 本文、`>`/`->`/`rm -rf /` のような他のスキャナーを誤検知させうる文字列を本文に含む場合を含む）と `<<"EOF"`（ダブルクォート）を `tool:gh_pr_write` 許可済みセッションでの positive case として固定する。演算子より前に実際の危険操作がある `git push --force <<'EOF' ... EOF` は本文の内容に関わらず引き続き block されること、`tool:gh_pr_write` が未承認の場合は同じ heredoc コマンドでも引き続き通常許可フローへ戻ること、および delimiter が unquoted な heredoc（`<<EOF`）は既知の未対応形として引き続き通常許可フローへ戻ること（回帰ではなく仕様）を negative case として固定する。

引用符付き `$(...)` にネストされた heredoc の認識（issue #258）については、`git commit -m "$(cat <<'EOF' ... EOF)"`（複数行コミットメッセージ、`tool:git_write` のセッション許可なしで無条件許可パターンにより承認されること）と、同じ形で heredoc 本文にアポストロフィ（`don't`）・括弧（`(#123)`）を含み `$(...)` 境界検出を壊さないことを positive case として固定する。delimiter が unquoted な heredoc が `$(...)` にネストされた場合は既存のトップレベル unquoted-delimiter 挙動と同様に通常許可フローへ戻ること、および heredoc の終端行より後、同じ `$(...)` の中に続く危険操作（例: heredoc の直後の `rm -rf /`）は masking の影響を受けず引き続き通常許可フローへ戻る（`$(...)` 内容全体を無条件許可しない）ことを negative case として固定する。

`--explain`（issue #283）については、named 関数に一致する安全なコマンド（`is_safe_unix_read_tool_command` 経由の positive 出力を含む）、どの named 関数にも session-approved にも一致しないコマンド（session-approved ファイル不在の状態も含む）、destructive guard で block されるコマンド、コマンド未指定時の usage メッセージ、session-approved fast path が成立するケース、および fast path は成立しないが session-approved と named 関数の両方の一致経路を1コマンド内で同時に踏むケース（`git status && git checkout foo`）を固定する。出力が PreToolUse JSON プロトコル（`{"decision": ...}`）を一切出力しないことも検証する。

このhookは完全なshell parserではない。安全に分類できない構文を自動承認対象へ広げず、通常許可フローへ戻すことを互換動作とする。任意コードを実行するbuild/test commandも自動承認しない。

根拠: `tests/hooks/test-approval-hooks.sh`

## 変更履歴（git log より自動生成）

- 8aeaa64 feat(#352): auto-approve WIP squash resets
- c146ead fix(#340): approve Codex permission requests
- 880ee07 feat(#301): consolidate /new-issue draft/label/creation approval into Step 4
- a38d7ad feat(#290): accept a single branch token in git fetch <remote> allow-shape
- 16babcc feat(#289): allow bare 'git checkout main' / 'git switch main' unconditionally
- c5776f2 feat(#297): scope tool:gh_issue_write/tool:gh_pr_write session grants to issue/PR number
- 5748c69 feat(#283): add --explain diagnostic mode to auto-approve-readonly.sh
- 8d684e6 fix(#280): remove 120-char truncation from auto-approve decision log
- 0685826 feat(#276): allowlist gh --version and mise current/ls/list in auto-approve hook
- 82b21e2 fix(#265): emit valid JSON on Codex fallback path in auto-approve-readonly.sh
- f096447 feat(#258): recognize heredocs nested inside quoted $(...) in _mask_quoted_heredoc_bodies
- 202a7eb refactor(#257): extract _heredoc_skip_end_index and make subshell span scanner heredoc-aware
- e8d33b3 feat(#254): recursively validate xargs and find -exec wrapped commands in auto-approve hook
- 87ce937 fix(#250): protect session-approved from auto-approved rm, tighten task.md Step 2 checklist

## work-run event helper の allow-shape

`is_safe_work_run_event_command()` はClaude/Codexのinstalled helper path、公開subcommand（`start|attach|emit|current`）、literal schema tokenだけを許可する。変数、`--strict`、alternate path、未知subcommand、空白値、shell syntaxは通常許可フローへ戻す。これによりinstrumentationの追加promptを防ぎつつ、任意script/commandの許可へ広げない。

根拠: `hooks/auto-approve-readonly.sh` (`is_safe_work_run_event_command`), `tests/hooks/test-approval-hooks.sh`
