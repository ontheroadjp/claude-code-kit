# Test Strategy

## 対象

このリポジトリには Bash で直接実行する shell tests が14本、pytest で実行する Python tests が `tests/scripts/` にある。`tests/hooks/test-approval-hooks.sh` と全shell scriptへのShellCheckはCI実行されるが、command contract tests・installer tests・pytestは現状ローカル検証のみである。

根拠: `tests/hooks/test-approval-hooks.sh`, `tests/commands/test-mtg.sh`, `tests/commands/test-coding-guidelines.sh`, `tests/commands/test-workflow-contracts.sh`, `tests/commands/test-work-multi.sh`, `tests/install/test-install.sh`, `tests/scripts/test-link-worktree-untracked.sh`, `tests/scripts/`, `site/package.json:4-8`, `.github/workflows/deploy.yml:17-52`, `.github/workflows/test.yml:1-18`

## Hook safety test

`tests/hooks/test-approval-hooks.sh` は destructive command block、read-only/session approval、session temp boundary、cleanup、working repo dynamic defense、guard JSON output を検証する。実行には `jq` と git repository が必要である。CI（`.github/workflows/test.yml`）では `main` への push と `pull_request` のたびに自動実行される（`timeout-minutes: 10`、ローカル実測で約4分）。

```bash
bash tests/hooks/test-approval-hooks.sh
```

根拠: `tests/hooks/test-approval-hooks.sh:1-1163`, `tests/README.md`, `.github/workflows/test.yml:1-18`

## Command workflow contract tests

Markdown command は直接実行可能な application code ではないため、重要な必須句と禁止操作を固定文字列で検査する。

```bash
bash tests/commands/test-mtg.sh
```

`test-mtg.sh` は exact agenda label routing、非線形の検討、明示指示だけでの `/new-issue`、ユーザー主導の close、command/skill contract を確認する。

根拠: `tests/commands/test-mtg.sh:1-57`

```bash
bash tests/commands/test-coding-guidelines.sh
```

`test-coding-guidelines.sh` はReact/Next.js layerの依存順、task/patch routing、代表anti-pattern、local pathやrepository名の混入防止を確認する。

根拠: `tests/commands/test-coding-guidelines.sh:1-53`

```bash
bash tests/commands/test-workflow-contracts.sh
```

`test-workflow-contracts.sh` は `docs-sync.md`・`init-docs.md`・`task.md`・`git-pr.md` 間の契約（HARD STOP からの自動委譲、standalone mode のデフォルト、`/task` が docs-sync の内部エスカレーションを意識しないこと、PR 作成責務が `/git-pr` にあること等）を静的検証する。

根拠: `tests/commands/test-workflow-contracts.sh:1-47`

```bash
bash tests/commands/test-work-multi.sh
```

`test-work-multi.sh` は `commands/work-multi.md` が `EnterWorktree` 呼び出しと `commands/work.md` への委譲のみで構成されゲート定義を重複していないこと、`skills/work-multi/SKILL.md` の scope guard、`commands/work.md` の worktree パスガードと `worktree-` prefix ベースのブランチ分類、`scripts/link-worktree-untracked.sh` の実行権限と `.git`/`.claude` 除外を確認する（issue #296、PR #304）。

根拠: `tests/commands/test-work-multi.sh:1-83`

```bash
bash tests/commands/test-task-manager.sh
bash tests/commands/test-git-pr-merge.sh
```

`test-task-manager.sh` はcomplete Draft setのapproved-head context、input-order delivery delegation、partial completion、documentation A/M/D/R、completion commentsを検証する。`test-git-pr-merge.sh` はstandalone/delegated approval、unknown commit、latest-main refresh、current-head CI/local validation、actual-branch conflict repair、local main prohibition、explicit squash deliveryを検証する。

根拠: `tests/commands/test-task-manager.sh:1-132`, `tests/commands/test-git-pr-merge.sh:1-81`

## Installer contract test

`tests/install/test-install.sh` は temporary fixture repository と isolated HOME を作成し、`install.sh` を2回実行する。symlink と hook migration に加え、`scripts/setup_statusline_for_codex.sh` が `~/.codex/config.toml` に4つの status itemを設定し、再実行しても結果が変わらないことを検証する。

```bash
bash tests/install/test-install.sh
```

`tests/install/test-setup-statusline-for-codex.sh` は fresh config、`[tui]` がない config、既存の複数行 `status_line` を持つ config を isolated HOME で検証する。既存 key と後続 table を維持し、2回目の実行で差分が生じないことも確認する。

```bash
bash tests/install/test-setup-statusline-for-codex.sh
```

根拠: `tests/install/test-install.sh:1-176`, `tests/install/test-setup-statusline-for-codex.sh:1-122`

## Worktree untracked-file link test

`tests/scripts/test-link-worktree-untracked.sh` は `scripts/link-worktree-untracked.sh` の symlink 挙動を、一時 git リポジトリを使った functional test で検証する（issue #296）。

```bash
bash tests/scripts/test-link-worktree-untracked.sh
```

トップレベル untracked ファイル/ディレクトリの symlink、tracked ディレクトリ配下にネストした untracked ディレクトリの symlink、`.git`/`.claude` の除外、再実行時の冪等性、および `hooks/lib/session-paths.sh` が解決可能な場合の manifest（`worktree-untracked-symlinks.txt`）書き出しを確認する（issue #318）。

根拠: `tests/scripts/test-link-worktree-untracked.sh:1-126`

## Log analysis script tests

`tests/scripts/` は `scripts/analyze_access.py` / `analyze_auto_approve.py` / `analyze_token_usage.py` のパース・集計ロジックを合成ログ fixture で検証する pytest テストである。`tests/scripts/conftest.py` が `scripts/` を `sys.path` に追加する。

```bash
python3 -m pytest tests/scripts/
```

根拠: `tests/scripts/test_analyze_access.py`, `tests/scripts/test_analyze_auto_approve.py`, `tests/scripts/test_analyze_token_usage.py`, `tests/scripts/conftest.py`

## Site build verification

CI と同等の site 検証は Node.js availability を確認してから VitePress build を実行する。

```bash
node --version
npm --version
cd site && npm ci
cd site && npm run docs:build
```

CI は Node.js 24 と `site/package-lock.json` を使う。

根拠: `.github/workflows/deploy.yml:17-42`, `site/package.json:4-14`

## Coverage と未確認事項

- coverage collection と threshold の定義は存在しない。
- `tests/hooks/test-approval-hooks.sh` は CI に登録されている。他の shell tests（`test-mtg.sh`, `test-coding-guidelines.sh`, `test-workflow-contracts.sh`, `test-work-multi.sh`, `test-task-manager.sh`, `test-git-pr-merge.sh`, installer/worktree tests）と pytest は CI に登録されていない。ただし全shell testsはShellCheck対象である。
- 上記を変更する場合は `site/package.json` または `.github/workflows/` の実体を更新し、この文書も再観測する。
