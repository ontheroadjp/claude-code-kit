# auto-approve-readonly hook specification

## 目的と安全境界

`hooks/auto-approve-readonly.sh` は Claude Code / Codex CLI の PreToolUse hook である。通常操作の不要な許可プロンプトを減らしつつ、自動承認を次の3種類に限定する。

1. 永続状態を変更しない読み取り専用操作
2. ローカルリポジトリの外に一切影響しない narrow な git write 操作（`git add`/`git commit -m`/`git fetch`。共有・remote 状態は変更しない）
3. 現在セッションでユーザーが承認したファイルまたはツールカテゴリに属する操作

この分類に確信を持てない操作は出力なしで終了し、クライアントの通常許可フローへ戻す。破壊的操作は allowlist より先に評価し、session-approved が存在しても block する。

根拠: `docs/L0_concept/policy.md`, `hooks/auto-approve-readonly.sh:709-1093`, `hooks/lib/approval-safety.sh`

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

## 判定順序

判定は次の順序で行う。後段の allowlist は前段の block / prompt 判定を上書きしない。

1. payload、session、agent、状態パスを解決する。
2. `Read` は常時承認する。
3. `Write` は session temp、承認ファイル自身、session-approved file、working repo の順に評価する。
4. `Edit` は session temp、session-approved file、working repo の順に評価する。
5. `apply_patch` は working repo 内であれば WIP commit 後に承認する。repo 外は通常許可フローへ戻す。
6. `Bash` 以外の未対応 tool は通常許可フローへ戻す。
7. `Bash` は session-approved fast path を最初に評価する（全 segment が session-approved の場合のみ即時承認）。
8. repo 内単一パスへの `rm -rf` は動的防御（WIP commit）後に承認する。
9. 共有 destructive guard を評価し、該当する場合は block する。
10. `/dev/null` redirect と escaped pipe を正規化する。
11. quote-aware にファイルへの write redirect（unquoted かつ `>&` ではない `>`）を検出した場合は通常許可フローへ戻す。
12. command を quote-aware に segment 分割する（`>&<fd番号|->` は fd 複製として background operator 扱いしない）。
13. 全 segment が読み取り専用・narrow な local git write（`git add`/`git commit -m`/`git fetch`）・または session-approved のいずれかの場合のみ承認する。

根拠: `hooks/auto-approve-readonly.sh:709-1093`

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

根拠: `hooks/auto-approve-readonly.sh:83-115`, `hooks/auto-approve-readonly.sh:718-821`

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
| Runtime | version 表示、`codex --version`/`--help`/`-h`、`bash -n <file>`・`node --check`/`-c <file>`・`command -v <name>`（他のフラグを含まない単一引数形のみ） | script / program 実行、`bash -n`・`node --check`・`command -v` へのフラグ追加や複数引数（denylist ではなく「厳密な単一引数形」の allowlist。node は long option のハイフン/アンダースコア表記が等価かつ `--experimental-config-file` 経由で preload 可能なため、危険フラグの列挙では網羅できない） |
| プロセス確認 | `kill -0 <数値pid...>`（シグナル0=生存確認のみ、実際には何も送信しない） | 数値以外のpid、負のpid（プロセスグループ指定）、`-0`以外のシグナル/フラグ |
| セッション一時ディレクトリ作成 | `mkdir -p <session tmp dir またはその配下、単一パスのみ>` | `-p`以外のフラグ、複数パス、session tmp dir 外 |
| curl | default GET / HEAD 相当 | custom method、data/form、upload、config、file output |
| npm | metadata照会、config取得、引数なしの `npm run` | script実行、publish、install、audit fix等 |
| journalctl | ログ照会全般 | `--vacuum-size/--vacuum-time/--vacuum-files`, `--rotate`, `--flush`, `--sync`, `--relinquish-var`, `--smart-relinquish-var`, `--setup-keys`, `--update-catalog`, `--force` |
| gsettings | `get`, `list-schemas`, `list-relocatable-schemas`, `list-keys`, `list-children`, `list-recursively`, `range`, `describe`, `writable` | `set`, `reset`, `reset-recursively`, `monitor` |
| gnome-extensions | `info`, `list` | `enable`, `disable`, `install`, `uninstall` 等 |
| dpkg（`is_safe_dpkg_query_command`） | `-l`/`--list`, `-L`/`--listfiles`, `-s`/`--status`, `-S`/`--search` のいずれか1つのみを含む形 | `-i`/`-r`/`-P`/`--configure` 等の変更系、上記フラグを2つ以上組み合わせた形 |
| Git local write（`is_safe_local_git_write_command`） | `git add <明示パス...>`、`git commit -m/--message "<message>"`（単一クォート文字列）、`git fetch` / `git fetch <remote単一トークン>` | `add`: `-A`/`--all`/`.`/`*`。`commit`: `-m`/`--message` 以外の任意フラグ（`--amend`/`--no-verify`/`-a` 等）。`fetch`: refspec（`:`）、`+`強制指定、複数トークン |

`git -C <directory>` は `-C` prefix を正規化した後、同じ Git 判定を適用する。

### `is_safe_local_git_write_command`: session-approved 不要な local git write

`git add`/`git commit`/`git fetch` は `tool:git_write`（session-approved カテゴリ）にも属するが、この3パターンに限っては**セッション同意なしで無条件承認**する専用関数 `is_safe_local_git_write_command` を `is_safe_git_read_command` の直後に追加している。

**なぜ無条件で安全か:** この3操作はローカルリポジトリの外に一切影響しない。`add` はステージングのみ、`commit` はローカル履歴への記録のみ、許可される `fetch` の形（引数なし、または remote 名のみ）はローカルの remote-tracking ref を更新するだけで working tree・push・共有状態には触れない。これは Write/Edit tool が working repo 内のファイルを既に無条件承認している設計（動的防御セクション参照）と同じ「共有状態への影響がない」境界線上にある。

一方で `git push`・`gh issue`/`gh pr` の書き込みは GitHub 上で他者から見える共有状態を変更するため、恒久 allowlist には追加せず `tool:git_write`/`tool:gh_issue_write`/`tool:gh_pr_write`（session-approved、1セッション1回のユーザー同意）に留める。

**allowlist-shape（denylist ではない）:** `docs/L0_concept/policy.md` の設計方針に従い、いずれの分岐も「危険フラグを列挙して除外する」のではなく「安全な形だけを正規表現全体でマッチさせる」positive shape である。

- `git add`: 各トークンが `-` 始まりでなく、かつ `.`/`*` 単独でもないことを要求する。1つでも該当すれば unsafe。
- `git commit`: セグメント全体が `git commit (-m|--message) "..."` または `git commit (-m|--message) '...'` に完全一致することを要求する（`$(...)` はこのチェックより前段で `__SUBSHELL_SAFE__` に置換・再帰検証済みのため、ヒアドキュメント経由の複数行メッセージもこの形に収まる）。
- `git fetch`: `git fetch` 単体、または `git fetch <remote>`（英数字始まりの単一トークン。`--all` のような `-` 始まりトークンは除外）のみ許可する。

根拠: `hooks/auto-approve-readonly.sh`（`is_safe_local_git_write_command`、`is_safe_git_read_command` 直後）, issue #221

### `is_safe_dpkg_query_command`: dpkg の read-only クエリ限定 allow-shape

`dpkg` は `-l`/`-L`/`-s`/`-S` のような read-only クエリと `-i`/`-r`/`-P`/`--configure` のような変更系操作を同一コマンドで混在させているため、`apt-cache`（変更系サブコマンドが一切存在しない）のように無条件では許可できない。`is_safe_dpkg_query_command` は、`-l`/`--list`・`-L`/`--listfiles`・`-s`/`--status`・`-S`/`--search` のうち**ちょうど1つ**が存在し、それ以外に `-` で始まるトークンが一切ないことを要求する。

**`git branch`/`git tag` の read-only-mode allow-shape より厳格な理由:** それらは「危険フラグを除外し、既知の read-only フラグが1つでもあれば許可」という形だが、dpkg では2つの許可フラグを組み合わせた場合（例: `dpkg -l -L pkg`）も意図的に拒否する。単一フラグのみを許可形状とすることで、フラグの組み合わせによる未検証の挙動変化を一切許容しない。

根拠: `hooks/auto-approve-readonly.sh`（`is_safe_dpkg_query_command`、`is_safe_for_in_list` 直後）, issue #233

次の mode はコマンド名が読み取り系でも常時許可しない。

- `find -delete/-exec/-execdir/-ok/-fprint*`
- `sed -i/--in-place` および script 内の `e` / `w` command
- `sort -o/--output`
- `yq -i/--inplace`
- `awk` の `system()`、外部 command を pipe する `getline`、`print`/`printf` の出力リダイレクト（`>` / `>>`）
- command を伴う `env`
- `date --set/-s`
- 値を指定する `hostname`
- `pytest`, `python -m pytest`

`curl` の短縮 option は単独形だけでなく結合形も検査する。`-so`、`-sO` のように file output や request body / upload / config を有効化する文字を含む option cluster は通常許可フローへ戻す。`-sSI` のような読み取り専用 cluster は引き続き承認する。

根拠: `hooks/auto-approve-readonly.sh:877-1078`

### write redirect 検出のクォート対応

判定順序 11 の write redirect 検出（`_has_unquoted_write_redirect`）は、`_has_variable_expansion` と同じ single/double quote + backslash escape の文法を再利用し、quote 追跡した上で unquoted な `>`（かつ直後が `&` ではないもの）だけを file-write redirect とみなす。これにより `awk -F: '$1>130 && $1<200'` のようにシングルクォート内で比較演算子として使われる `>` を誤って redirect と判定しない。

**副作用として閉じた抜け穴:** この quote-aware 化により、シングルクォート内の `>` を無条件に write redirect とみなしていた旧実装が偶発的に防いでいた `awk` 自身の `print`/`printf` 出力リダイレクト（例: `awk 'BEGIN { print 1 > "/tmp/unsafe" }'`）が、この修正だけでは auto-approve されてしまう状態が一時的に生じた。これは awk 固有 allowlist 側の `\b(print|printf)\b.*>` チェックで別途塞いでいる（上表「常時許可しない mode」参照）。`print`/`printf` キーワードの後にどこかで `>` が現れる segment は無条件に unsafe とする、意図的に粗い判定である（`print "a>b"` のような文字列リテラル内の `>` も誤検知するが、false prompt-fallback は無害であり、file write の見逃しの方が問題であるため）。

根拠: `hooks/auto-approve-readonly.sh:221-258`, `hooks/auto-approve-readonly.sh:961-970`

### `>&` の fd 複製認識

`split_shell_segments` の `&` ハンドラは、直前の文字が `>` かつ直後が数値 fd または `-`（境界は空白・`;`・`&`・`|`・文字列末尾）である場合、その `&` を fd 複製（`2>&1`, `1>&2`, `>&-` 等）とみなし、background operator としての分割・`__UNSUPPORTED_BACKGROUND_OPERATOR__` 付与を行わない。

**なぜ「数値 fd または `-`」に限定するか:** bash の `>&word` は word が数値または `-` の場合のみ fd 複製であり、それ以外（`>&somefile` 等）は `&>word` と同義のファイル書き込みリダイレクトである。このため判定は狭く保ち、`>&` に続く語が数値/`-` 以外の場合は引き続き background operator 分岐（結果として unsafe な `__UNSUPPORTED_BACKGROUND_OPERATOR__` segment を生成し、複合 command 全体を prompt fallback させる）に落ちる。

根拠: `hooks/auto-approve-readonly.sh:482-497`

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

根拠: `hooks/auto-approve-readonly.sh:166-209`, `hooks/auto-approve-readonly.sh:509-523`, `hooks/auto-approve-readonly.sh:877-1078`

### session-approved tool category

`session-approved` に次の category がある場合だけ、対応する write action を承認する。

| category | 許可内容 | 除外 |
|---|---|---|
| `tool:git_write` | add, commit, merge, fetch, `pull --ff-only`, stash push/pop/apply, non-force push, branch checkout/switch, non-force branch operation | force option / `+refspec` push, pull without `--ff-only`, pull rebase/no-ff/force, checkoutによるpath復元, checkout/switch force, forced branch deletion |
| `tool:gh_issue_write` | issue create/edit/close/delete/comment/reopen | その他 |
| `tool:gh_pr_write` | PR create/edit/close/comment/reopen/ready/review/checkout/merge | その他 |

destructive guard に該当する操作は category があっても block する。

根拠: `hooks/auto-approve-readonly.sh:610-651`, `hooks/lib/approval-safety.sh`

## 複合 command

newline、`;`、`|`、`||`、`&&` を引用符の外側だけで分割し、全 segment を個別評価する。single / double quote 内の `|` は正規表現等の文字として保持する。read-onlyな `if` / `then` / `else` / `fi` / `for` / `do` / `done` は各 body を個別評価する。

### `for` / `do` / `done` ループの評価

`for VAR in LIST; do ...; done` は `if`/`then`/`else`/`fi` と同じ「制御構造キーワードは透過的に扱い、本体だけを個別に allowlist 判定する」設計で扱う。

- `for VAR in LIST` ヘッダーは `is_safe_for_in_list` が形状のみを確認して safe と判定する。このヘッダー自体はループ変数への代入を行うだけで何も実行しないため、`LIST` の内容そのものを検査する必要がない。`LIST` に含まれる `$(...)` は、この判定に到達する前に `is_safe_segment` 冒頭の再帰検証で既に safe 確認・プレースホルダー置換済みである。
- `do` は `then`/`else` と同じ prefix-strip 方式（`do` を取り除いた残りを `is_safe_segment` に再帰的に渡す）、`done` は `fi` と同じ bare keyword（本体を持たない終端）として扱う。
- ループ本体は既存の `;`/`&&`/`||`/`|` によるセグメント分割で個別セグメントに分かれるため、本体内の各コマンドは他の command と同一の read-only allowlist で判定される。`for` である無条件承認は一切ない — `for f in a b; do touch unsafe; done` のように本体が allowlist に一致しない場合は通常許可フローへ戻る。

**スコープ外（意図的にフォールスルー）:** C-style `for ((i=0;i<n;i++))` は `is_safe_for_in_list` の `in` 必須パターンに一致しないため対象外のまま通常確認へ戻る（`split_shell_segments` は算術コンテキスト内の `;` を認識せず、対応した場合ヘッダーを誤分割してしまうため）。`while`/`until`/`case`/`select`、および `in` を省略した `for VAR; do ...; done`（暗黙の `"$@"` 参照）も同様に未対応のまま。

根拠: `hooks/auto-approve-readonly.sh:400-421`, `hooks/auto-approve-readonly.sh:950-965`, issue #224

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

### 常時ブロックする構文

次は安全に分類せず通常許可フローへ戻す。

- 単独の background operator `&`
- backtick `` ` `` による command substitution（常時ブロック）
- process substitution `<()` / `>()`（常時ブロック）
- `$()` の中身に unsafe なコマンドが 1 つでも含まれる場合
- 未対応のshell構文
- 1つでも未許可のsegmentを含む複合command

根拠: `hooks/auto-approve-readonly.sh:144-147`, `hooks/auto-approve-readonly.sh:274-367`, `hooks/auto-approve-readonly.sh:553-607`, `hooks/auto-approve-readonly.sh:1083-1093`

## decision とログ

| 結果 | Claude | Codex |
|---|---|---|
| approve | `{"decision":"approve"}` | `{"decision":"allow"}` |
| prompt fallback | stdoutなし | stdoutなし |
| destructive block | reason付きblock JSON | reason付きblock JSON |

decision log は `logs/auto-approve/YYYY-MM.log` に次の形式で追記する。process fallback の session は `n/a` とする。

```text
[timestamp] agent=claude|codex session=<id|n/a> result=<result> tool=<tool> duration_ms=<ms|NA> <detail>
```

`duration_ms` はスクリプト冒頭（`payload=$(cat)` の前）で取得した `$EPOCHREALTIME`（bash 5.0+ のビルトイン変数、サブプロセスなし）を起点に、`log_decision()` 呼び出し時点までの経過ミリ秒を純粋な bash 整数演算（`10#` prefix で usec の leading zero を octal 誤解釈しないようにする）で計算したものである。`$EPOCHREALTIME` が使えない bash（5.0未満。例: macOS デフォルトの `/bin/bash` 3.2）では `duration_ms=NA` とし、計測不能を正直に記録する（サブプロセスベースの代替計測は行わない）。`scripts/analyze_auto_approve.py` の `LINE_RE` はこのフィールドを任意グループとして扱うため、`duration_ms` を持たない旧フォーマットのログ行も引き続き解析できる。集計・レポートへの反映は issue #218 のスコープ。

`detail` は `cut -c1-120` で切り詰めてからログへ書き込む。`cut -c` は non-UTF-8-aware なロケール（`LC_ALL=C` 等）ではバイト単位に振る舞うため、日本語などマルチバイト文字を含む command を境界で切ると不正な UTF-8 バイト列を生成し、`grep` 等ロケール依存ツールがログをバイナリ扱いして検索に失敗する原因になっていた。`truncate_utf8_safe()` は `cut` の直後に `iconv -f UTF-8 -t UTF-8 -c` を通し、切り詰め境界に残った不完全なマルチバイトシーケンスを除去する（`iconv` 不在時は切り詰め結果をそのまま返すフォールバック）。

根拠: `hooks/auto-approve-readonly.sh:64-73`, `hooks/auto-approve-readonly.sh:530-574`

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
  approval_safety → block
  正規化・write redirect → user_prompt
  segment allowlist → approve
  user_prompt
```

根拠: `hooks/auto-approve-readonly.sh:718-1093`

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

`tests/hooks/test-approval-hooks.sh` は常時許可、session-approved、複合command、write mode、destructive block、session temp、cleanup、working repo dynamic defense をpositive / negativeの両面から検証する。Bash allowlist の境界では、通常の `sed -e`、plain `awk getline`、read-only curl option cluster、non-force Git 操作、`git merge-base`、`pgrep`、`gh api`（GET-only）、`gsettings get`系、`journalctl`、`gnome-extensions info/list`、`bash -n`、`node --check`/`-c` を positive case とし、`sed e/w`、pipe-based `awk getline`、file output を含む curl cluster、Git force variants、`git merge-base --output`、`gsettings set/reset`、`journalctl --vacuum-*/--rotate/--flush/--update-catalog/--smart-relinquish-var`、`gh api -X/-XPOST/-f/-fkey=value/--input`（区切り文字なしの結合形も含む）、`gnome-extensions enable/disable`、`bash -n` へのフラグ追加・複数引数、`node --check` へのフラグ追加・複数引数（アンダースコア表記や `--experimental-config-file` 経由の preload を含む）を negative case として固定する。`for`/`do`/`done`（issue #224）については、read-only body を持つ `for VAR in LIST; do ...; done`（`;` 区切り・改行区切りの両方）を positive case、unsafe body を持つ for ループ、C-style `for ((i=0;i<n;i++))`、`$()` 経由で unsafe コマンドを list に埋め込む for ループ、`in` を省略した `for VAR; do ...; done` を negative case として固定する。

variable expansion の除外については、`node --check $ARGS` 型の報告された bypass に加え、`bash -n`・`curl`・`gh api`・`git diff --output`・`sed`・`find`・`sort`・`date`・`journalctl`・`yq`・`awk` への同型 bypass を negative case として固定し、`cat $FILE`・`grep ... $FILE`・シングルクォート awk script 内の `$1` が引き続き auto-approve されることを positive case で固定する。加えて、`git -C $DIR` operand への変数隠蔽、double-quoted 変数の単一フラグ密輸、シングルクォート内バックスラッシュの誤エスケープ、ダブルクォート文字列内のシングルクォートによるクォート状態誤遷移、`_extract_subshell_contents`/`_strip_subshells` のエスケープ未対応（escaped `"` をクォート終了と誤認し後続の変数参照が silently drop される）、同2関数が depth=0 でシングルクォートを追跡しないため single-quoted literal 内の `$(` を実際の subshell 開始と誤認する問題（例: `curl '$(' $OPTS ...`）、同2関数が depth=0 でダブルクォートを追跡しないため double-quoted 文字列内のリテラルな `'` により後続の本物の `$(` を検出し損ねる問題（例: `cat "foo'$(touch ...)"`）、およびネストした `$(...)` でクォート状態を push/pop しないため外側の double-quoted 文字列の中の nested substitution が正しく閉じられない問題（例: `X=$(printf '%s' "$(touch ...)")`）という、レビューで発見された8件の追加 bypass を negative case として固定する。統一 tokenizer への再設計（issue #200）に伴い、`saw_dollar` look-ahead flag がエスケープ消費時にリセットされず depth が 0 に戻らなくなる問題（例: `cat $(printf "$\"(" $(touch /tmp/unsafe))`）と、ANSI-C クォート（`$'...'`）が通常の `'...'` として扱われエスケープされた `\'` を閉じクォートと誤認する問題（例: `cat $'foo\'bar'$(touch /tmp/unsafe)`）の2件を追加の negative case として固定する。

issue #208 で修正した quote-unaware write-redirect 誤検知と `>&` fd 複製誤判定については、`awk -F: '$1>130 && $1<200'` のようなシングルクォート内比較演算子と `cat ... 2>&1` / `cat ... 1>&2` を positive case、`awk 'BEGIN { print 1 > "/tmp/unsafe" }'` のような awk 自身の出力リダイレクトと `cmd >&somefile`（fd 複製ではなく実ファイル書き込み）を negative case として固定する。同時に追加した allowlist（`command -v <name>`、`codex --version`/`--help`、`kill -0 <数値pid...>`、session tmp dir 配下限定の `mkdir -p`）についても、それぞれ許可される最小形を positive case、スコープ外の形（複数引数の `command -v`、`codex` の他サブコマンド、`-0` 以外のシグナルや負のpid/プロセスグループ指定を伴う `kill`、`-p` なし・複数パス・session tmp dir 外を対象とする `mkdir`）を negative case として固定する。

`log_decision` のマルチバイト切り詰めについては、`LC_ALL=C` でバイト単位 `cut -c` を強制し、120文字境界を跨ぐ日本語コマンドのログ行が valid UTF-8 かつ `grep -qE` で検出可能であることを検証する回帰テストを持つ。

このhookは完全なshell parserではない。安全に分類できない構文を自動承認対象へ広げず、通常許可フローへ戻すことを互換動作とする。任意コードを実行するbuild/test commandも自動承認しない。

根拠: `tests/hooks/test-approval-hooks.sh:1-826`

## 変更履歴（git log より自動生成）

- 15877ae feat(#238): add strings/readlink/ss/apt-cache/desktop-file-validate/man/diff/sleep to the auto-approve hook's read-only tools allowlist
- d3b2129 fix(#231): add sha256sum to the auto-approve hook's read-only tools allowlist
- d5a823a feat(#224): add for/do/done allow-shape to auto-approve-readonly.sh
- 377cdd3 feat(#221): allow-shape auto-approve for local git writes, add review-resolve session gate
- 13987a8 feat(#219): add duration_ms timing to auto-approve-readonly.sh decision log
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
- 6c041c6 fix(#194): close gh api/journalctl/node --check allowlist bypasses
