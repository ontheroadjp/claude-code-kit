# /work-multi

`commands/work.md` と全く同じワークフローを、`EnterWorktree` で作成した専用の worktree 内で実行するための、意図的な並行セッション利用向けエントリポイントです。並行セッションが同じ working tree を共有すると、一方の `git checkout` がもう一方の作業中ファイルを書き換えてしまう衝突が起こり得ます（issue #296）。worktree で物理的に working tree を分離することでこれを防ぎます。

`commands/work.md` 自体の判定ロジックは変更しません。ここで行うのは、`commands/work.md` を Read する前に専用 worktree へ切り替えることだけです。

---

## Step 0: worktree への切り替え

### 0.1 現在の作業ディレクトリを記録する

```bash
pwd
```

出力された絶対パスを `ORIGINAL_WORKDIR` として以降のステップでリテラル値として使用する（CLAUDE.md の resolve-then-embed 規約に従う）。

### 0.2 EnterWorktree を実行する

`EnterWorktree` を `path` を指定せずに呼び出す（常に新規 worktree を作成する。既存 worktree への再入場はスコープ外）。これによりセッションの作業ディレクトリが新しい worktree（`.claude/worktrees/<name>`、`origin/<default-branch>` から分岐したブランチ `worktree-<name>`）へ切り替わる。

### 0.3 untracked ファイル/ディレクトリを symlink する

`git worktree add`（`EnterWorktree` の内部実装）は tracked ファイルのみをチェックアウトし、untracked/gitignored ファイル・ディレクトリはコピーしない。このリポジトリ群は特定のプロジェクト専用ではなく Claude Code / Codex CLI が任意のリポジトリで使う実行環境基盤であるため、対象リポジトリ固有の untracked パスを個別に把握することはできない。そのため `.git`・`.claude`（`EnterWorktree` 自身が worktree を格納する予約ディレクトリ）を除く全ての untracked/ignored パスを一律で symlink する:

```bash
bash scripts/link-worktree-untracked.sh "<0.1 で得た ORIGINAL_WORKDIR の絶対パス>"
```

（`scripts/link-worktree-untracked.sh` は新しい worktree にも tracked ファイルとして存在するため、worktree 切り替え後のカレントディレクトリからそのまま実行できる。詳細: `docs/L3_implementation/scripts/link-worktree-untracked.sh.md`）

**既知の限界**: この symlink はセッション中に書き換わる untracked ディレクトリ（例: `node_modules` 等のパッケージマネージャ依存ディレクトリ）にも適用される。複数の `/work-multi` セッションが同じ symlink 先へ同時に書き込み操作（`npm install` 等）を行うと、worktree 隔離で防ごうとしている共有可変状態の衝突がそのディレクトリに限り再発し得る。並行セッションで同じ依存ディレクトリへの書き込みを伴う操作を同時実行しないこと。

---

## Step 1: /work への委譲

1. `commands/work.md` を Read する。
2. その内容を一字一句そのまま実行する。再解釈・簡略化・他ワークフローとの統合はしない。
3. 指示が自分の想定と矛盾する場合は `commands/work.md` に従う。

## Scope Guard

- `commands/work.md`・`task.md`・`patch.md` をこのファイルから編集しない。
- worktree 切り替え以外のロジック（ゲート確認・ルーティング判定・実装フロー）を重複定義しない。

## 完了時の扱い

`commands/work.md`（および委譲先の `task.md`/`patch.md`）の完了報告に加えて、worktree のパスをユーザーへ報告する。`ExitWorktree` はユーザーから明示的に指示された場合のみ呼び出す。セッション終了時に worktree に残っている場合は harness が keep/remove をユーザーに確認する。
