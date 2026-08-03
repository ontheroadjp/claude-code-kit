# Project Overview

## リポジトリの実態

`core-toolkit-for-claude` は、Claude Code / Codex CLI 向けの AI 開発運用ツールキットである。主な実体は Markdown のコマンド仕様、Codex skill ラッパー、Claude Code hooks、共通テンプレート、VitePress ドキュメントサイトで構成される。

根拠: `README.md:1-15`, `commands/*.md`, `skills/*/SKILL.md`, `hooks/*.sh`, `templates/*.md`, `site/package.json:1-14`

## 主要機能

| 領域 | 実装 | 役割 | 根拠 |
|---|---|---|---|
| 作業入口 | `commands/work.md` | main への checkout、workspace gate、report-review/task/patch ルーティング | `commands/work.md:7-143` |
| report 評価 | `commands/report-review.md` | `report` label の issue を read-only で評価し、意見と提案を標準出力へ提示 | `commands/report-review.md:1-91` |
| ログ分析 | `commands/analyze-access.md`, `analyze-auto-approve.md`, `analyze-token-usage.md` | `logs/access`・`logs/auto-approve`・`logs/token-usage` を `scripts/analyze_*.py` で集計し、KPIダッシュボード→Key Findings & Proposals→Evidence の順で構成したレポートと HTML を `logs/reports/` へ出力する read-only workflow | `commands/analyze-access.md:1-85`, `scripts/analyze_access.py:1-6` |
| docs あり実装 | `commands/task.md` | issue 確認/生成、プラン承認、実装、L3 per-file doc、`/docs-sync`・`/git-pr` 引き継ぎ | `commands/task.md:30-184` |
| 軽微修正 | `commands/patch.md` | docs 変更不要な修正を branch + commit で完了し、必要時 task へエスカレーション | `commands/patch.md:1-111` |
| docs 同期 | `commands/docs-sync.md` | `git diff main...HEAD` を事実として docs/README を最小更新・commit し、結果を session temp へ記録 | `commands/docs-sync.md:1-173` |
| docs 初期化 | `commands/init-docs.md` | repo 再観測、repo profile 生成、L0-L3 docs 生成、整合性検証、ユーザー確認後の draft PR | `commands/init-docs.md:1-420` |
| review 対応 | `commands/review-resolve.md` | PR review コメント取得、対応方針選択、実装/返信/push | `commands/review-resolve.md:1-175` |
| issue トリアージ | `commands/triage-issues.md` | open issue を stale/inconsistent/duplicated/unclear/ready に分類し、ユーザー承認後に各アクションを実行するスタンドアロン入口 | `commands/triage-issues.md:1-187` |
| issue 作成 | `commands/new-issue.md` | 漠然としたアイデアから issue を作成する任意 pre-step | `commands/new-issue.md:1-129` |
| coding 原則 | `commands/coding-*.md` | general / py / js / ts の実装規約 | `commands/coding-general.md:1-3`, `commands/coding-ts.md:1-12` |
| Codex skills | `skills/*/SKILL.md` | 19個の wrapper が対応する command markdown を Source of Truth として実行する | `skills/*/SKILL.md` 実体一覧 |
| hooks | `hooks/*.sh` | 自動承認、破壊的操作 guard、ログ、セッション cleanup | `hooks/auto-approve-readonly.sh`, `hooks/guard-destructive-cmd.sh`, `hooks/cleanup-session.sh` |
| tests | `tests/hooks/*.sh`, `tests/commands/*.sh`, `tests/install/*.sh` | hook safety、declarative workflow、installer symlink contract を shell で検証 | `tests/` 実体一覧 |
| site | `site/` | VitePress による公開ドキュメントサイト | `site/package.json:1-14`, `site/.vitepress/config.mts:1-183` |

## 技術スタック

- コマンド仕様: Markdown。根拠: `commands/*.md`
- hooks / 補助スクリプト: Bash（`hooks/*.sh`, `scripts/*.sh`）と Python（`scripts/analyze_*.py`, `scripts/lib/`、ログ解析用）。根拠: `hooks/*.sh`, `scripts/*.sh`, `scripts/analyze_access.py:1-6`, `install.sh:1-3`
- 公開サイト: VitePress + npm。根拠: `site/package.json:1-14`, `site/package-lock.json`
- CI: GitHub Actions + Node.js 24 + npm。根拠: `.github/workflows/deploy.yml:24-37`
- 外部 CLI: `git`, `gh`, `jq`, `node`, `npm`, `bc`, `codex`, `curl`。根拠: `commands/codex-review.md:67-72`, `hooks/notify-slack.sh:38-44`, `scripts/statusline.sh:10-31`, `.github/workflows/deploy.yml:24-37`

## エントリポイント

- AI 作業の通常入口は `/work`。根拠: `commands/work.md:1-4`, `README.md:63-85`
- report issue は `/work #N` から `/report-review` へ委譲される。根拠: `commands/work.md:53-68`, `commands/report-review.md:1-3`
- `/work`（および委譲先の `/task`）のゴールは ready PR の作成までであり、作成後の自律 review は行わない。根拠: `commands/git-pr.md:62-65`, `CLAUDE.md:15`
- PR review コメント対応は `/review-resolve #N`。根拠: `commands/review-resolve.md:1-6`
- idea から issue を作る任意入口は `/new-issue`。根拠: `commands/new-issue.md:1-9`
- open issue を整理する任意入口は `/triage-issues`。根拠: `commands/triage-issues.md:1-9`
- VitePress site の CI entry は `.github/workflows/deploy.yml` の `npm run docs:build`。根拠: `.github/workflows/deploy.yml:31-37`
- アプリケーション runtime の `main.*` / `server.*` / `app.*` は存在しない。実行入口は Markdown commands、shell installers/tests、VitePress npm scripts、GitHub Actions である。根拠: `rg --files -uu -g '!.git/**'`、`site/package.json:4-8`、`.github/workflows/deploy.yml:17-52`

## 依存関係

`site/package.json` は本番依存として `@fortawesome/fontawesome-free`、開発依存として `vitepress` を宣言する。lock file から `@fortawesome/fontawesome-free` は 6.7.2、`vitepress` は 1.6.4 が解決されている。

根拠: `site/package.json:9-14`, `site/package-lock.json:765-766`, `site/package-lock.json:2486-2487`

## 未確認事項

現時点で docs に混在させた未確認事項はない。
