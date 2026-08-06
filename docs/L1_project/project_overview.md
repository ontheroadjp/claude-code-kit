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
| docs 初期化 | `commands/init-docs.md` | repo 再観測、repo profile 生成、L0-L3 docs 生成（L0 は存在しない場合のみ）、整合性検証、ユーザー確認後の draft PR | `commands/init-docs.md:1-423` |
| L0 昇格 | `commands/concept-maker.md` | `docs/.ai/l0_candidates.md` の L0 昇格候補をユーザーとの壁打ちと明示的承認を経て `docs/L0_concept/` へ追記する唯一の経路。branch + commit → ユーザーが ff-merge | `commands/concept-maker.md:1-92` |
| review 対応 | `commands/review-resolve.md` | PR review コメント取得、対応方針選択、実装/返信/push | `commands/review-resolve.md:1-175` |
| auto-approve候補起票 | `commands/auto-approve-hazard-scan.md` | `/analyze-auto-approve` の候補コマンドを `hooks/auto-approve-readonly.sh --explain` で診断し、AIがハザードチェックリストを作成、既知ハザードなしの候補のみユーザー一括承認後に `auto-approve-candidate` issue を起票するスタンドアロン入口。hook自体は変更しない | `commands/auto-approve-hazard-scan.md:1-162` |
| issue トリアージ | `commands/triage-issues.md` | open issue を stale/inconsistent/duplicated/unclear/ready に分類し、ユーザー承認後に各アクションを実行するスタンドアロン入口 | `commands/triage-issues.md:1-178` |
| issue 作成 | `commands/new-issue.md` | 漠然としたアイデアから issue を作成する任意 pre-step | `commands/new-issue.md:1-126` |
| coding 原則 | `commands/coding-*.md` | general / py / js / ts / sh に React / Next.js framework layerを合成する汎用実装規約 | `commands/coding-general.md:1-52`, `commands/coding-react.md:1-43`, `commands/coding-nextjs.md:1-43` |
| Codex skills | `skills/*/SKILL.md` | 24個の wrapper が対応する command markdown を Source of Truth として実行する | `skills/*/SKILL.md` 実体一覧 |
| hooks | `hooks/*.sh` | 自動承認、破壊的操作 guard、ログ、セッション cleanup | `hooks/auto-approve-readonly.sh`, `hooks/guard-destructive-cmd.sh`, `hooks/cleanup-session.sh` |
| tests | `tests/hooks/*.sh`, `tests/commands/*.sh`, `tests/install/*.sh`, `tests/scripts/*.py` | hook safety、declarative workflow、installer symlink contract を shell で、ログ解析を pytest で検証 | `tests/README.md`, `tests/scripts/test_analyze_access.py`, `tests/scripts/test_analyze_auto_approve.py`, `tests/scripts/test_analyze_token_usage.py` |
| site | `site/` | VitePress による公開ドキュメントサイト | `site/package.json:1-14`, `site/.vitepress/config.mts:1-183` |

## 技術スタック

- コマンド仕様: Markdown。根拠: `commands/*.md`
- hooks / 補助スクリプト: Bash（`hooks/*.sh`, `scripts/*.sh`）と Python（`scripts/analyze_*.py`, `scripts/lib/`、ログ解析用）。根拠: `hooks/*.sh`, `scripts/*.sh`, `scripts/analyze_access.py:1-6`, `install.sh:1-3`
- 公開サイト: VitePress + npm。根拠: `site/package.json:1-14`, `site/package-lock.json`
- CI: GitHub Actions + Node.js 24 + npm。根拠: `.github/workflows/deploy.yml:24-37`
- 外部 CLI / runtime: `git`, `gh`, `jq`, `node`, `npm`, `python3`, `bc`, `codex`, `curl`。根拠: `commands/codex-review.md:65-87`, `commands/analyze-access.md:27-35`, `hooks/notify-slack.sh:35-45`, `scripts/statusline.sh:10-31`, `.github/workflows/deploy.yml:24-37`

## エントリポイント

- AI 作業の通常入口は `/work`。根拠: `commands/work.md:1-4`, `README.md:63-85`
- report issue は `/work #N` から `/report-review` へ委譲される。根拠: `commands/work.md:53-68`, `commands/report-review.md:1-3`
- `/work`（および委譲先の `/task`）のゴールは ready PR の作成までであり、作成後の自律 review は行わない。根拠: `commands/git-pr.md:62-65`, `CLAUDE.md:15`
- PR review コメント対応は `/review-resolve #N`。根拠: `commands/review-resolve.md:1-6`
- idea から issue を作る任意入口は `/new-issue`。根拠: `commands/new-issue.md:1-9`
- open issue を整理する任意入口は `/triage-issues`。根拠: `commands/triage-issues.md:1-9`
- `logs/auto-approve/*.log` から allowlist 拡張候補を洗い出し、ユーザー一括承認後に `auto-approve-candidate` issue を起票する任意入口は `/auto-approve-hazard-scan`。hook自体は変更しない。根拠: `commands/auto-approve-hazard-scan.md:1-9`
- `/docs-sync` が L0 昇格候補ありを案内した場合の任意入口は `/concept-maker`。L0（`docs/L0_concept/`）への唯一の AI 書き込み経路（`/init-docs` の初回新規作成を除く）。根拠: `commands/concept-maker.md:1-92`
- VitePress site の CI entry は `.github/workflows/deploy.yml` の `npm run docs:build`。根拠: `.github/workflows/deploy.yml:31-37`
- アプリケーション runtime の `main.*` / `server.*` / `app.*` は存在しない。実行入口は Markdown commands、shell installers/tests、VitePress npm scripts、GitHub Actions である。根拠: `rg --files -uu -g '!.git/**'`、`site/package.json:4-8`、`.github/workflows/deploy.yml:17-52`

## 依存関係

`site/package.json` は本番依存として `@fortawesome/fontawesome-free`、開発依存として `vitepress` を宣言する。lock file から `@fortawesome/fontawesome-free` は 6.7.2、`vitepress` は 1.6.4 が解決されている。

根拠: `site/package.json:9-14`, `site/package-lock.json:765-766`, `site/package-lock.json:2486-2487`

## 未確認事項

現時点で docs に混在させた未確認事項はない。
