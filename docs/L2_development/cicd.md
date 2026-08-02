# CI/CD

## 対象 workflow

このリポジトリで確認できる CI/CD 定義は `.github/workflows/deploy.yml` の 1 件である。workflow 名は `Deploy VitePress site to GitHub Pages` で、`main` への push と手動実行 (`workflow_dispatch`) で起動する。

根拠: `.github/workflows/deploy.yml:1-7`

## 権限と同時実行制御

GitHub Pages へ公開するため、workflow は `contents: read`、`pages: write`、`id-token: write` を要求する。concurrency group は `pages` で、進行中の deploy を中断しない設定である。

根拠: `.github/workflows/deploy.yml:8-15`

## build job

`build` job は `ubuntu-latest` で実行される。手順は checkout、Node.js 24 setup、npm cache 設定、`site/` での `npm ci`、`site/` での `npm run docs:build`、`site/.vitepress/dist` の Pages artifact upload である。

なぜこの構成か: 公開サイトの実体は `site/package.json` が定義する VitePress project であり、lock file は `site/package-lock.json` にある。そのため CI は repository root ではなく `site/` を working directory として npm install/build を実行し、VitePress の build output を Pages artifact として渡す。

根拠: `.github/workflows/deploy.yml:17-42`, `site/package.json:4-14`, `site/package-lock.json:1-13`

## deploy job

`deploy` job は `build` job に依存し、`github-pages` environment へ `actions/deploy-pages@v5` で deploy する。公開 URL は `steps.deployment.outputs.page_url` から environment URL に設定される。

根拠: `.github/workflows/deploy.yml:44-53`

## ローカルでの同等確認

CI の build と同等の主要検証は次のコマンドで行う。

```bash
cd site && npm ci
cd site && npm run docs:build
```

`npm run docs:build` は `site/package.json` の `docs:build` script で `vitepress build` を実行する。

根拠: `.github/workflows/deploy.yml:31-37`, `site/package.json:4-8`

## 未確認事項

CI に専用 test job はない。repository には shell tests が存在するが、この workflow は VitePress build だけを実行する。ローカル test 手順は `docs/L2_development/test.md` に分離する。

根拠: `tests/` 実体一覧、`site/package.json:4-14`, `.github/workflows/deploy.yml:17-53`
