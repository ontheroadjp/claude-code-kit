# /work-multi

`commands/work.md` と全く同じワークフローを、`EnterWorktree` で作成した専用の worktree 内で実行するための、意図的な並行セッション利用向けエントリポイントです。並行セッションが同じ working tree を共有すると、一方の `git checkout` がもう一方の作業中ファイルを書き換えてしまう衝突が起こり得ます（issue #296）。worktree で物理的に working tree を分離することでこれを防ぎます。

`commands/work.md` 自体の判定ロジックは変更しません。ここで行うのは、`commands/work.md` を Read する前の専用 worktree への切り替えだけです。親 issue の検出、未完了の子 issue の依存関係確認、次に実行すべき子 issue の報告と終了は、`commands/work.md` が一元的に担います。

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

**venv/.venv の例外**: Python の仮想環境（`venv`・`.venv`）はセッション中に `pip install` 等で書き込まれるため、`node_modules` と同様に symlink 経由で共有すると書き込み衝突を招く。この2つの path 名に限り `link` ではなく `venv <relative-path>` サブコマンドを使い、`uv` で worktree 内に独立した実体の仮想環境を構築する（symlink は作らない）:

```bash
bash ~/.claude/scripts/link-worktree-untracked.sh venv ".venv"
```

Codex CLI では `~/.codex/scripts/` を使う。`venv` サブコマンドは、指定 path の basename が `venv`・`.venv` のいずれでもない場合、path が既に存在する場合、または対象 path が worktree の `.gitignore` で ignore されていない場合に失敗する（誤って `git add` の対象になることを防ぐため）。構築には `uv` があれば `uv venv` を、なければ標準ライブラリの `python3 -m venv`（pip 同梱）にフォールバックする。成功した path は他の lazy link と同じ manifest に記録され、`worktree-status.sh` の除外対象になる。

**書き込み境界（必須）**: lazy link した path は読み取り専用として扱う。単独・並行を問わず、symlink 経由でその path を書き換えるコマンドは実行してはならない。`npm install` など package manager による依存 directory への書き込みもこれに含まれる。書き込みが必要な path は link する前に、worktree 内へ独立して作成する。symlink を含む worktree を削除しても、リンク先の元 working tree に既に書き込まれた変更は元に戻らない。`venv` サブコマンドで構築した venv/.venv はこの制限の対象外であり、symlink ではなく worktree 内の独立した実体であるため、`pip install`・`uv pip install` 等の書き込みを行ってよい。

---

## Step 1: /work への委譲

1. `commands/work.md` を Read する。
2. その内容を一字一句そのまま実行する。再解釈・簡略化・他ワークフローとの統合はしない。
3. 指示が自分の想定と矛盾する場合は `commands/work.md` に従う。

## Scope Guard

- `commands/work.md`・`task.md`・`patch.md` をこのファイルから編集しない。
- 親 issue の検出・子 issue の依存関係判定を含むロジック（ゲート確認・ルーティング判定・実装フロー）を重複定義しない。

## 完了時の扱い

`commands/work.md`（および委譲先の `task.md`/`patch.md`）の完了報告に加えて、worktree のパスをユーザーへ報告する。`ExitWorktree` はユーザーから明示的に指示された場合のみ呼び出す。セッション終了時に worktree に残っている場合は harness が keep/remove をユーザーに確認する。
