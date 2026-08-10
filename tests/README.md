# tests/

hook および各種スクリプトの動作検証スクリプトを置くディレクトリ。

## ディレクトリ構造

```
tests/
├── hooks/
│   └── test-approval-hooks.sh   ← PreToolUse hook の自動テストスクリプト
├── commands/
│   ├── test-report-review.sh      ← report workflow contract
│   ├── test-coding-guidelines.sh  ← coding guideline contract
│   ├── test-workflow-contracts.sh ← docs-sync/init-docs/task/git-pr 間の契約
│   └── test-work-multi.sh         ← work-multi contract（issue #296）
├── install/
│   └── test-install.sh          ← installer symlink contract の自動テストスクリプト
└── scripts/
    ├── test-link-worktree-untracked.sh ← untracked symlink の functional test（issue #296）
    └── test_analyze_*.py            ← ログ解析 scripts の pytest suite
```

## test-approval-hooks.sh

`hooks/auto-approve-readonly.sh`、`hooks/guard-destructive-cmd.sh`、
`hooks/cleanup-session.sh` の動作を shell レベルで検証する。

### テストケースの分類

| カテゴリ | 内容 |
|---|---|
| 破壊的 Bash のブロック | `rm -rf /` などの破壊的コマンドが block decision を返すことを確認 |
| session-approved があっても破壊的操作はブロック | session-approved を持っていても破壊的操作は通過しない |
| 読み取り専用の承認 | `ls`・`git status` などが自動承認されることを確認 |
| session-approved による承認 | 事前登録したツール・ファイルが自動承認されることを確認 |
| session temp 配下の Write/Edit 承認 | セッション temp ディレクトリ内の書き込みが承認されることを確認 |
| session temp 範囲外のフォールバック | temp 範囲外パスはユーザー確認へ戻ることを確認 |
| symlink 解決 | symlink 先が temp 外の場合はフォールバックすることを確認 |
| cleanup hook の動作 | Stop 時に `session-approved` が削除されることを確認 |
| write-effect/ambiguous のフォールバック | 分類不能なコマンドがユーザー確認へ戻ることを確認 |
| guard-destructive-cmd.sh の JSON 出力 | JSON block decision が正しく出力されることを確認 |
| working repo 動的防御 | repo 内 Write/Edit/apply_patch・rm -rf が承認または WIP commit されることを確認 |

### 実行方法

```bash
bash tests/hooks/test-approval-hooks.sh
```

全テスト PASS で終了コード 0 を返す。FAIL があると終了コード 1 で終了し、失敗したテストケース名を表示する。

## command contract tests

`test-report-review.sh` はreport routingとread-only境界、`test-coding-guidelines.sh` はReact/Next.js layerの依存順・routing・repository非依存性、`test-workflow-contracts.sh` は docs-sync/init-docs/task/git-pr 間の契約、`test-work-multi.sh` は work-multi.md・skills/work-multi/SKILL.md・work.md の worktree ガードとブランチ分類・link-worktree-untracked.sh を固定文字列で検証する（issue #296）。

```bash
bash tests/commands/test-report-review.sh
bash tests/commands/test-coding-guidelines.sh
bash tests/commands/test-workflow-contracts.sh
bash tests/commands/test-work-multi.sh
```

## test-link-worktree-untracked.sh

`scripts/link-worktree-untracked.sh` の symlink 挙動を一時 git リポジトリで functional に検証する（issue #296）。

```bash
bash tests/scripts/test-link-worktree-untracked.sh
```

## test-install.sh

fixture repository と一時 HOME を作成して `install.sh` を2回実行し、Claude Code / Codex CLI の template symlink、legacy target 非作成、再実行の idempotence を検証する。

```bash
bash tests/install/test-install.sh
```

### 前提条件

- `hooks/auto-approve-readonly.sh`、`hooks/guard-destructive-cmd.sh`、`hooks/cleanup-session.sh` が存在すること
- `jq` がインストールされていること
- git リポジトリ内で実行すること
