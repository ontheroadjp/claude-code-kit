# CI/CD

## 対象 workflow

このリポジトリには CI/CD 定義が3件ある。

- `.github/workflows/deploy.yml`（`Deploy VitePress site to GitHub Pages`）: `main` への push と手動実行 (`workflow_dispatch`) で起動し、VitePress site を GitHub Pages へ deploy する。
- `.github/workflows/shellcheck.yml`（`ShellCheck`）: `main` への push と `pull_request` で起動し、`node_modules`・`.git` を除く全 `*.sh` に `shellcheck -x` を実行する。
- `.github/workflows/test.yml`（`Approval Hooks Test`）: `main` への push と `pull_request` で起動し、`tests/hooks/test-approval-hooks.sh`（PreToolUse hook の安全性を検証する最重要テスト）を実行する。`timeout-minutes: 10`（ローカル実測で約4分）。

根拠: `.github/workflows/deploy.yml:1-7`, `.github/workflows/shellcheck.yml:1-18`, `.github/workflows/test.yml:1-18`

## 権限と同時実行制御

`deploy.yml` は GitHub Pages へ公開するため `contents: read`、`pages: write`、`id-token: write` を要求する。concurrency group は `pages` で、進行中の deploy を中断しない設定である。`shellcheck.yml`・`test.yml` は追加の権限宣言を持たない（デフォルトの `contents: read` のみ）。

根拠: `.github/workflows/deploy.yml:8-15`, `.github/workflows/shellcheck.yml:1-18`, `.github/workflows/test.yml:1-18`

## build job

`build` job は `ubuntu-latest` で実行される。手順は checkout、Node.js 24 setup、npm cache 設定、`site/` での `npm ci`、`site/` での `npm run docs:build`、`site/.vitepress/dist` の Pages artifact upload である。

なぜこの構成か: 公開サイトの実体は `site/package.json` が定義する VitePress project であり、lock file は `site/package-lock.json` にある。そのため CI は repository root ではなく `site/` を working directory として npm install/build を実行し、VitePress の build output を Pages artifact として渡す。

根拠: `.github/workflows/deploy.yml:17-42`, `site/package.json:4-14`, `site/package-lock.json:1-13`

## deploy job

`deploy` job は `build` job に依存し、`github-pages` environment へ `actions/deploy-pages@v5` で deploy する。公開 URL は `steps.deployment.outputs.page_url` から environment URL に設定される。

根拠: `.github/workflows/deploy.yml:44-53`

## shellcheck job

`shellcheck` job は `ubuntu-latest` で実行される。手順は checkout の後、`node_modules`・`site/node_modules`・`.git` を除く全 `*.sh` を `find` で列挙し、`shellcheck -x` を実行する。

根拠: `.github/workflows/shellcheck.yml:8-18`

## approval-hooks job

`approval-hooks` job（`test.yml`）は `ubuntu-latest` で `timeout-minutes: 10` の制限付きで実行される。手順は checkout の後 `bash tests/hooks/test-approval-hooks.sh` を実行するのみである。このテストは `hooks/auto-approve-readonly.sh`・`hooks/guard-destructive-cmd.sh`・`hooks/cleanup-session.sh` の安全性契約を検証する（詳細: `docs/L2_development/test.md`）。ローカル実測では約4分で完了する。

根拠: `.github/workflows/test.yml:8-18`, `tests/hooks/test-approval-hooks.sh:1-1163`

## ローカルでの同等確認

CI の build と同等の主要検証は次のコマンドで行う。

```bash
cd site && npm ci
cd site && npm run docs:build
```

`npm run docs:build` は `site/package.json` の `docs:build` script で `vitepress build` を実行する。shellcheck job と approval-hooks job の同等確認は以下である。

```bash
find . -not -path "./node_modules/*" -not -path "./site/node_modules/*" -not -path "./.git/*" -iname "*.sh" -print0 | xargs -0 shellcheck -x
bash tests/hooks/test-approval-hooks.sh
```

根拠: `.github/workflows/deploy.yml:31-37`, `site/package.json:4-8`, `.github/workflows/shellcheck.yml:15-18`, `.github/workflows/test.yml:15-18`

## 未確認事項

`tests/hooks/test-approval-hooks.sh` は CI（`approval-hooks` job）で実行されるが、`tests/commands/test-mtg.sh`・`tests/install/test-install.sh`・`tests/scripts/`（pytest）は依然として CI に登録されておらずローカル検証のみである。ローカル test 手順は `docs/L2_development/test.md` に分離する。

根拠: `tests/` 実体一覧、`.github/workflows/test.yml:1-18`, `.github/workflows/shellcheck.yml:1-18`, `.github/workflows/deploy.yml:1-53`
