# auto-approve-readonly hook specification

## 目的と安全境界

`hooks/auto-approve-readonly.sh` は Claude Code / Codex CLI の PreToolUse hook である。通常操作の不要な許可プロンプトを減らしつつ、自動承認を次の2種類に限定する。

1. 永続状態を変更しない読み取り専用操作
2. 現在セッションでユーザーが承認したファイルまたはツールカテゴリに属する操作

この分類に確信を持てない操作は出力なしで終了し、クライアントの通常許可フローへ戻す。破壊的操作は allowlist より先に評価し、session-approved が存在しても block する。

根拠: `docs/L0_concept/policy.md`, `hooks/auto-approve-readonly.sh:619-951`, `hooks/lib/approval-safety.sh`

## セッションと実行元の解決

session ID は次の優先順で解決し、英数字・`.`・`_`・`-` 以外を `_` に置換する。

1. `CLAUDE_CODE_KIT_SESSION_ID`
2. payload の `session_id`
3. payload の `transcript_path` を hash 化した ID
4. `CODEX_THREAD_ID` を hash 化した ID
5. `process-<PPID>` fallback

承認ファイルの既定値は `${XDG_STATE_HOME:-$HOME/.local/state}/claude-code-kit/sessions/<session-id>/session-approved`、一時領域の既定値は `/tmp/claude-code-kit/<session-id>/` である。process fallback 以外では承認ファイルの解決結果を `current-session-approved-path` に通知する。

Codex は hook の呼出しパスまたは `CODEX_MANAGED_BY_NPM`、`CODEX_MANAGED_BY_BUN`、`CODEX_CI`、`CODEX_THREAD_ID` で判定する。それ以外は Claude とする。

根拠: `hooks/auto-approve-readonly.sh:8-81`

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
11. ファイルへの write redirect を検出した場合は通常許可フローへ戻す。
12. command を quote-aware に segment 分割する。
13. 全 segment が読み取り専用または session-approved の場合のみ承認する。

根拠: `hooks/auto-approve-readonly.sh:619-951`

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

根拠: `hooks/auto-approve-readonly.sh:83-115`, `hooks/auto-approve-readonly.sh:628-716`

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
| Shell navigation / test | `cd`, `test`, `[ ... ]`, read-only `if` | command/process substitution、operatorを含む test |
| Unix read tools | `ls`, `cat`, `head`, `tail`, grep 系、`rg`, `fd`, `wc`, `cut`, `tr`, `sed`, `awk`, `sort`, `jq`, `yq`, `nl`, `pgrep` など | 下記のwrite/execute mode |
| Runtime | version 表示、`bash -n <file>`・`node --check`/`-c <file>`（他のフラグを含まない単一引数形のみ） | script / program 実行、`bash -n`・`node --check` へのフラグ追加や複数引数（denylist ではなく「厳密な単一引数形」の allowlist。node は long option のハイフン/アンダースコア表記が等価かつ `--experimental-config-file` 経由で preload 可能なため、危険フラグの列挙では網羅できない） |
| curl | default GET / HEAD 相当 | custom method、data/form、upload、config、file output |
| npm | metadata照会、config取得、引数なしの `npm run` | script実行、publish、install、audit fix等 |
| journalctl | ログ照会全般 | `--vacuum-size/--vacuum-time/--vacuum-files`, `--rotate`, `--flush`, `--sync`, `--relinquish-var`, `--smart-relinquish-var`, `--setup-keys`, `--update-catalog`, `--force` |
| gsettings | `get`, `list-schemas`, `list-relocatable-schemas`, `list-keys`, `list-children`, `list-recursively`, `range`, `describe`, `writable` | `set`, `reset`, `reset-recursively`, `monitor` |
| gnome-extensions | `info`, `list` | `enable`, `disable`, `install`, `uninstall` 等 |

`git -C <directory>` は `-C` prefix を正規化した後、同じ Git 判定を適用する。

次の mode はコマンド名が読み取り系でも常時許可しない。

- `find -delete/-exec/-execdir/-ok/-fprint*`
- `sed -i/--in-place` および script 内の `e` / `w` command
- `sort -o/--output`
- `yq -i/--inplace`
- `awk` の `system()` および外部 command を pipe する `getline`
- command を伴う `env`
- `date --set/-s`
- 値を指定する `hostname`
- `pytest`, `python -m pytest`

`curl` の短縮 option は単独形だけでなく結合形も検査する。`-so`、`-sO` のように file output や request body / upload / config を有効化する文字を含む option cluster は通常許可フローへ戻す。`-sSI` のような読み取り専用 cluster は引き続き承認する。

根拠: `hooks/auto-approve-readonly.sh:785-936`

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

根拠: `hooks/auto-approve-readonly.sh:133-193`, `hooks/auto-approve-readonly.sh:358-371`, `hooks/auto-approve-readonly.sh:785-936`

### session-approved tool category

`session-approved` に次の category がある場合だけ、対応する write action を承認する。

| category | 許可内容 | 除外 |
|---|---|---|
| `tool:git_write` | add, commit, merge, fetch, `pull --ff-only`, stash push/pop/apply, non-force push, branch checkout/switch, non-force branch operation | force option / `+refspec` push, pull without `--ff-only`, pull rebase/no-ff/force, checkoutによるpath復元, checkout/switch force, forced branch deletion |
| `tool:gh_issue_write` | issue create/edit/close/delete/comment/reopen | その他 |
| `tool:gh_pr_write` | PR create/edit/close/comment/reopen/ready/review/checkout/merge | その他 |

destructive guard に該当する操作は category があっても block する。

根拠: `hooks/auto-approve-readonly.sh:520-561`, `hooks/lib/approval-safety.sh`

## 複合 command

newline、`;`、`|`、`||`、`&&` を引用符の外側だけで分割し、全 segment を個別評価する。single / double quote 内の `|` は正規表現等の文字として保持する。read-onlyな `if` / `then` / `else` / `fi` は各 body を個別評価する。

### `$()` subshell の評価

`is_safe_segment` は `$()` を含む segment を次の手順で評価する。

1. `_extract_subshell_contents` で各トップレベル `$(...)` の中身を抽出する（文字単位でパース、ネスト・クォート追跡あり）
2. `_subshells_are_safe` で各中身を `is_safe_segment` に再帰的に渡し、全て read-only であることを確認する
3. 全て safe であれば `_strip_subshells` で `$(...)` を `__SUBSHELL_SAFE__` プレースホルダーに置換し、外側のコマンドをさらに評価する
4. 外側コマンドが純粋な変数代入（`VAR=value` 形式で unquoted space を含まない）であれば safe と判定する

結果として `PR_BODY=$(cat file)` や `SESSION_ID=$(basename "$(dirname "$P")")` は自動承認される。

**既知の制限:** `_extract_subshell_contents` は depth=0 でシングルクォートを追跡しない。`grep -E 'pattern_with_$(foo)' file` のような single-quoted literal 内の `$(` は subshell として誤検出される。これは保守的（過剰ブロック）であり、許容できるトレードオフとして維持する。

### 常時ブロックする構文

次は安全に分類せず通常許可フローへ戻す。

- 単独の background operator `&`
- backtick `` ` `` による command substitution（常時ブロック）
- process substitution `<()` / `>()`（常時ブロック）
- `$()` の中身に unsafe なコマンドが 1 つでも含まれる場合
- 未対応のshell構文
- 1つでも未許可のsegmentを含む複合command

根拠: `hooks/auto-approve-readonly.sh:128-131`, `hooks/auto-approve-readonly.sh:200-353`, `hooks/auto-approve-readonly.sh:403-457`, `hooks/auto-approve-readonly.sh:941-951`

## decision とログ

| 結果 | Claude | Codex |
|---|---|---|
| approve | `{"decision":"approve"}` | `{"decision":"allow"}` |
| prompt fallback | stdoutなし | stdoutなし |
| destructive block | reason付きblock JSON | reason付きblock JSON |

decision log は `logs/auto-approve/YYYY-MM.log` に次の形式で追記する。process fallback の session は `n/a` とする。

```text
[timestamp] agent=claude|codex session=<id|n/a> result=<result> tool=<tool> <detail>
```

`detail` は `cut -c1-120` で切り詰めてからログへ書き込む。`cut -c` は non-UTF-8-aware なロケール（`LC_ALL=C` 等）ではバイト単位に振る舞うため、日本語などマルチバイト文字を含む command を境界で切ると不正な UTF-8 バイト列を生成し、`grep` 等ロケール依存ツールがログをバイナリ扱いして検索に失敗する原因になっていた。`truncate_utf8_safe()` は `cut` の直後に `iconv -f UTF-8 -t UTF-8 -c` を通し、切り詰め境界に残った不完全なマルチバイトシーケンスを除去する（`iconv` 不在時は切り詰め結果をそのまま返すフォールバック）。

根拠: `hooks/auto-approve-readonly.sh:64-75`, `hooks/auto-approve-readonly.sh:470-500`

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

根拠: `hooks/auto-approve-readonly.sh:628-951`

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

`tests/hooks/test-approval-hooks.sh` は常時許可、session-approved、複合command、write mode、destructive block、session temp、cleanup、working repo dynamic defense をpositive / negativeの両面から検証する。Bash allowlist の境界では、通常の `sed -e`、plain `awk getline`、read-only curl option cluster、non-force Git 操作、`git merge-base`、`pgrep`、`gh api`（GET-only）、`gsettings get`系、`journalctl`、`gnome-extensions info/list`、`bash -n`、`node --check`/`-c` を positive case とし、`sed e/w`、pipe-based `awk getline`、file output を含む curl cluster、Git force variants、`git merge-base --output`、`gsettings set/reset`、`journalctl --vacuum-*/--rotate/--flush/--update-catalog/--smart-relinquish-var`、`gh api -X/-XPOST/-f/-fkey=value/--input`（区切り文字なしの結合形も含む）、`gnome-extensions enable/disable`、`bash -n` へのフラグ追加・複数引数、`node --check` へのフラグ追加・複数引数（アンダースコア表記や `--experimental-config-file` 経由の preload を含む）を negative case として固定する。

variable expansion の除外については、`node --check $ARGS` 型の報告された bypass に加え、`bash -n`・`curl`・`gh api`・`git diff --output`・`sed`・`find`・`sort`・`date`・`journalctl`・`yq`・`awk` への同型 bypass を negative case として固定し、`cat $FILE`・`grep ... $FILE`・シングルクォート awk script 内の `$1` が引き続き auto-approve されることを positive case で固定する。加えて、`git -C $DIR` operand への変数隠蔽、double-quoted 変数の単一フラグ密輸、シングルクォート内バックスラッシュの誤エスケープ、ダブルクォート文字列内のシングルクォートによるクォート状態誤遷移、`_extract_subshell_contents`/`_strip_subshells` のエスケープ未対応（escaped `"` をクォート終了と誤認し後続の変数参照が silently drop される）という、レビューで発見された5件の追加 bypass を negative case として固定する。

`log_decision` のマルチバイト切り詰めについては、`LC_ALL=C` でバイト単位 `cut -c` を強制し、120文字境界を跨ぐ日本語コマンドのログ行が valid UTF-8 かつ `grep -qE` で検出可能であることを検証する回帰テストを持つ。

このhookは完全なshell parserではない。安全に分類できない構文を自動承認対象へ広げず、通常許可フローへ戻すことを互換動作とする。任意コードを実行するbuild/test commandも自動承認しない。

根拠: `tests/hooks/test-approval-hooks.sh:1-584`

## 変更履歴（git log より自動生成）

- ca76400 fix: add escape-awareness to subshell quote tracking in auto-approve hook
- 0ed05e5 fix(#196): fix quote-state desync when a double-quoted string contains a single quote
- 32610ca fix(#196): fix variable-expansion guard gaps found in review
- a04b853 fix(#196): close unquoted variable expansion bypass in auto-approve allowlist
- e740c91 fix(#194): replace node/bash syntax-check denylist with strict single-arg allowlist
- 6c041c6 fix(#194): close gh api/journalctl/node --check allowlist bypasses
- 3655fd5 feat(#194): extend read-only allowlist and fix multibyte log truncation
- 9d1d78f fix(#156): harden auto-approval boundary checks
- 975df69 feat(#183): allow $() subshells when content is read-only
- b2320ec chore: auto-approve update_plan and log webrun payload
