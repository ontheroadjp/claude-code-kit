# /work-multi

`commands/work.md` と全く同じワークフローを、`EnterWorktree` で作成した専用の worktree 内で実行するための、意図的な並行セッション利用向けエントリポイントです。並行セッションが同じ working tree を共有すると、一方の `git checkout` がもう一方の作業中ファイルを書き換えてしまう衝突が起こり得ます（issue #296）。worktree で物理的に working tree を分離することでこれを防ぎます。

`commands/work.md` 自体の判定ロジックは変更しません。ここで行うのは、`commands/work.md` を Read する前の専用 worktree への切り替えと、親 issue が指定された場合の実装対象の子 issue の決定だけです。

---

## Step 0: worktree への切り替え

### 0.1 現在の作業ディレクトリを記録する

```bash
pwd
```

出力された絶対パスを `ORIGINAL_WORKDIR` として記録する。これは Step 0.3 の lazy linker `prepare` 引数にのみリテラル値として使用する（CLAUDE.md の resolve-then-embed 規約に従う）。

### 0.2 EnterWorktree を実行する

`EnterWorktree` を `path` を指定せずに呼び出す（常に新規 worktree を作成する。既存 worktree への再入場はスコープ外）。これによりセッションの作業ディレクトリが新しい worktree（`.claude/worktrees/<name>`、`origin/<default-branch>` から分岐したブランチ `worktree-<name>`）へ切り替わる。

切り替え後は、新しい worktree を CWD のまま使用する。共有 checkout に `cd` したり、`git -C "$ORIGINAL_WORKDIR"` を使ったりしてはならない。`commands/work.md` の Read、現状調査、Git 操作はすべてこの worktree から実行する。

### 0.3 lazy linker を初期化する

`git worktree add`（`EnterWorktree` の内部実装）は tracked ファイルのみをチェックアウトする。開始時点では untracked/ignored ファイル・ディレクトリを symlink せず、元 worktree の絶対パスだけを current session に記録して lazy linker を初期化する。多くの作業は tracked file だけで完結し、`node_modules` のような大きな ignored directory を不要に処理しないためである:

Claude Code では次を実行する:

```bash
bash ~/.claude/scripts/link-worktree-untracked.sh prepare "<0.1 で得た ORIGINAL_WORKDIR の絶対パス>"
```

Codex CLI では次を実行する:

```bash
bash ~/.codex/scripts/link-worktree-untracked.sh prepare "<0.1 で得た ORIGINAL_WORKDIR の絶対パス>"
```

`install.sh` が toolkit の `scripts/link-worktree-untracked.sh` をこれらの agent 別パスへ symlink として配布するため、対象 consumer repo にこのスクリプトが tracked file として存在する必要はない。詳細: `docs/L3_implementation/scripts/link-worktree-untracked.sh.md`

作業中に untracked/ignored path が必要になった場合に限り、agent は次を実行する（例: `site/node_modules`）:

```bash
bash ~/.claude/scripts/link-worktree-untracked.sh link "site/node_modules"
```

Codex CLI では `~/.codex/scripts/` を使う。linker は source 側でその path が untracked/ignored であること、相対 path が `.git`・`.claude`・親 directory traversal を含まないこと、worktree 側に衝突する実体がないことを検証する。作成した path だけを `${SESSION_TMP_DIR}/worktree-untracked-symlinks.txt` に一度だけ記録する。`commands/work.md` G-2・`commands/task.md` Phase 2 の `worktree-status.sh` は、この manifest と完全一致する path またはその親 directory だけを自動除外する。manifest が空なら status は通常どおりであり、単体 `/work` の挙動も変わらない。

**書き込み境界（必須）**: lazy link した path は読み取り専用として扱う。単独・並行を問わず、symlink 経由でその path を書き換えるコマンドは実行してはならない。`npm install` など package manager による依存 directory への書き込みもこれに含まれる。書き込みが必要な path は link する前に、worktree 内へ独立して作成する。symlink を含む worktree を削除しても、リンク先の元 working tree に既に書き込まれた変更は元に戻らない。

---

## Step 1: 親 issue から実装対象を決定する

`/work-multi #<issue番号>` のように issue 番号が指定された場合、まず次を実行してその issue が親 issue か確認する。`subIssues` は GitHub の native sub-issue、`body` は既存の task list（`- [ ] #<issue番号>`）を確認するために使う。

```bash
gh issue view <issue番号> --json number,title,body,subIssues
```

- `subIssues.nodes[].number` と、本文の未完了 task list にある同一リポジトリの `#<issue番号>` を親の子 issue として収集する。同じ番号は一度だけ扱い、native sub-issue を先、task list を本文の出現順で続ける。
- 子 issue が 0 件なら、指定された issue 番号をそのまま `/work` へ渡す（従来どおり）。
- 子 issue が 1 件以上ある場合、各子 issue に対して次を実行し、`state` と GitHub の native dependency を取得する。

```bash
gh issue view <子issue番号> --json number,title,state,blockedBy
```

- `state` が `OPEN` であり、`blockedBy.nodes` の全 issue が `CLOSED` である子 issue だけを「実装可能」とする。親の子 issue 外にある blocker も未完了なら実装可能ではない。
- 実装可能な子 issue が複数ある場合は、上記の収集順で最初の 1 件を選ぶ。この順序を固定することで、並行セッションでも選択が再現可能になる。
- 実装可能な子 issue が 0 件の場合は、各子 issue の状態と未完了 blocker を報告して終了する。`/work` を呼び出したり、任意の子 issue を推測で選択したりしてはならない。
- GitHub の取得に失敗した場合、または `subIssues` / `blockedBy` が利用できない CLI・権限環境の場合は、エラーを報告して終了する。task list や本文中の語句から依存関係を推測してはならない。

子 issue を選んだ場合は、以降の `/work` 呼び出しでは親 issue 番号ではなく、選んだ子 issue 番号を「ユーザーが明示した issue 番号」として扱う。選択結果（親 issue、候補一覧、各 blocker、選択理由）をユーザーへ報告してから Step 2 に進む。

## Step 2: /work への委譲

1. `commands/work.md` を Read する。
2. その内容を一字一句そのまま実行する。再解釈・簡略化・他ワークフローとの統合はしない。
3. 指示が自分の想定と矛盾する場合は `commands/work.md` に従う。

## Scope Guard

- `commands/work.md`・`task.md`・`patch.md` をこのファイルから編集しない。
- 親 issue の子 issue 選択以外のロジック（ゲート確認・ルーティング判定・実装フロー）を重複定義しない。

## 完了時の扱い

`commands/work.md`（および委譲先の `task.md`/`patch.md`）の完了報告に加えて、worktree のパスをユーザーへ報告する。`ExitWorktree` はユーザーから明示的に指示された場合のみ呼び出す。セッション終了時に worktree に残っている場合は harness が keep/remove をユーザーに確認する。
