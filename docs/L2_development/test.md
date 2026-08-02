# Test Strategy

## 対象

このリポジトリには Bash で直接実行する shell tests が4本ある。package.json に test script はなく、GitHub Actions も shell tests を実行しないため、現状はローカル検証である。

根拠: `tests/hooks/test-approval-hooks.sh`, `tests/commands/test-pr-review.sh`, `tests/commands/test-report-review.sh`, `tests/install/test-install.sh`, `site/package.json:4-8`, `.github/workflows/deploy.yml:17-52`

## Hook safety test

`tests/hooks/test-approval-hooks.sh` は destructive command block、read-only/session approval、session temp boundary、cleanup、working repo dynamic defense、guard JSON output を検証する。実行には `jq` と git repository が必要である。

```bash
bash tests/hooks/test-approval-hooks.sh
```

根拠: `tests/hooks/test-approval-hooks.sh:1-407`, `tests/README.md`

## Command workflow contract tests

Markdown command は直接実行可能な application code ではないため、重要な必須句と禁止操作を固定文字列で検査する。

```bash
bash tests/commands/test-pr-review.sh
bash tests/commands/test-report-review.sh
```

`test-pr-review.sh` は別 agent routing、HEAD SHA binding、reviewer identity、最大 round、merge/main 操作禁止を確認する。`test-report-review.sh` は exact report label routing、read-only boundary、標準出力 sections、command/skill catalog 整合性を確認する。

根拠: `tests/commands/test-pr-review.sh:1-67`, `tests/commands/test-report-review.sh:1-72`

## Installer contract test

`tests/install/test-install.sh` は temporary fixture repository と isolated HOME を作成し、`install.sh` を2回実行する。repository の `templates/*.md` が `~/.claude/templates/` と `~/.codex/templates/` の両方へ個別 symlink されること、旧 `~/.config/claude-code-kit/templates` が作成されないこと、再実行しても結果が変わらないことを検証する。

```bash
bash tests/install/test-install.sh
```

根拠: `tests/install/test-install.sh:1-71`, `tests/README.md`

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
- shell tests は CI に登録されていない。
- 上記を変更する場合は `site/package.json` または `.github/workflows/` の実体を更新し、この文書も再観測する。

## Dependency audit observation

2026-08-02 の `npm audit --json` は current lockfile に total 4 vulnerabilities（moderate 2、high 2）を報告した。direct dependency では VitePress 1.6.4 が transitive Vite の影響を受け、transitive packages は Vite、esbuild、PostCSS である。npm は PostCSS に fix available、Vite / esbuild / VitePress には fix unavailable と報告した。

この観測は依存更新の許可を意味しない。再評価時は `site/package-lock.json` と最新の `npm audit --json` を確認し、upgrade は別 task としてユーザー承認を得る。

根拠: `site/package-lock.json`、2026-08-02 実行の `npm audit --json`
