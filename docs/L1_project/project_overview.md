# Project Overview

## リポジトリの実態

`core-toolkit-for-claude` は、Claude Code / Codex CLI 向けの AI 開発運用ツールキットである。主な実体は Markdown のコマンド仕様、Codex skill ラッパー、Claude Code hooks、共通テンプレート、VitePress ドキュメントサイトで構成される。

根拠: `README.md:1-15`, `commands/*.md`, `skills/*/SKILL.md`, `hooks/*.sh`, `templates/*.md`, `site/package.json:1-14`

## 主要機能

| 領域 | 実装 | 役割 | 根拠 |
|---|---|---|---|
| 実装入口 | `commands/work.md` | main への checkout、workspace gate、agenda/mtg/task/patch ルーティング | `commands/work.md:1-160` |
| agenda 対話 | `commands/mtg.md` | `agenda` label の issue を人間主導で検討し、明示指示時のみ起案へ進む | `commands/mtg.md:1-77` |
| ログ分析 | `commands/analyze-access.md`, `analyze-auto-approve.md`, `analyze-token-usage.md` | `logs/access`・`logs/auto-approve`・`logs/token-usage` を `scripts/analyze_*.py` で集計し、KPIダッシュボード→Key Findings & Proposals→Evidence の順で構成したレポートと HTML を `logs/reports/` へ出力する read-only workflow | `commands/analyze-access.md:1-85`, `scripts/analyze_access.py:1-6` |
| docs あり実装 | `commands/task.md` | issue 確認/生成、プラン承認、実装、L3 per-file doc、`/docs-sync`・`/git-pr` 引き継ぎ | `commands/task.md:30-184` |
| 軽微修正 | `commands/patch.md` | docs 変更不要な修正を branch + commit で完了し、必要時 task へエスカレーション | `commands/patch.md:1-111` |
| docs 同期 | `commands/docs-sync.md` | `git diff main...HEAD` を事実として docs/README を最小更新・commit し、結果を session temp へ記録 | `commands/docs-sync.md:1-173` |
| docs 初期化 | `commands/init-docs.md` | repo 再観測、repo profile 生成、L0-L3 docs 生成（L0 は存在しない場合のみ）、整合性検証、ユーザー確認後の draft PR | `commands/init-docs.md:1-423` |
| L0 昇格 | `commands/concept-maker.md` | `docs/.ai/l0_candidates.md` の L0 昇格候補をユーザーとの壁打ちと明示的承認を経て `docs/L0_concept/` へ追記する唯一の経路。branch + commit → ユーザーが ff-merge | `commands/concept-maker.md:1-92` |
| review 対応 | `commands/review-resolve.md` | PR review コメント取得、対応方針選択、実装/返信/push | `commands/review-resolve.md:1-175` |
| reviewed PR delivery | `commands/git-pr-merge.md` | approved headを固定し、owned worktreeでlatest-main refresh、current-head validation、explicit squash mergeを行う | `commands/git-pr-merge.md:1-147` |
| batch executor | `commands/task-manager.md` | 1〜3 issueのsource PRを並行準備し、承認後に `/git-pr-merge`へ入力順で委譲してdocumentationを同期する | `commands/task-manager.md:1-412` |
| ハザード候補起票 | `commands/analyze-hazard-scan.md` | auto-approve と access のログを分析し、source 固有の診断とハザードチェックリストにより、既知ハザードなしの候補のみユーザー一括承認後に `hazard-candidate` issue を起票するスタンドアロン入口。hook自体は変更しない | `commands/analyze-hazard-scan.md:1-171` |
| issue トリアージ | `commands/triage-issues.md` | open issue を stale/inconsistent/duplicated/unclear/ready に分類し、ユーザー承認後に各アクションを実行するスタンドアロン入口 | `commands/triage-issues.md:1-178` |
| ハザード候補レビュー | `commands/triage-issues-for-hazard.md` | `hazard-candidate` label 付き open issue を一覧化し、source 固有のハザード分析を開示、yes/no ゲートを経て yes の場合は `hazard-candidate` → `triage-approved` へ label を swap した上で `/work #N` の実行を案内するスタンドアロン入口。`/work` は自身で呼ばない | `commands/triage-issues-for-hazard.md:1-115` |
| issue 作成 | `commands/new-issue.md` | 漠然としたアイデアから issue を作成する任意 pre-step | `commands/new-issue.md:1-126` |
| coding 原則 | `commands/coding-*.md` | general / py / js / ts / sh に React / Next.js framework layerを合成する汎用実装規約 | `commands/coding-general.md:1-52`, `commands/coding-react.md:1-43`, `commands/coding-nextjs.md:1-43` |
| Codex skills | `skills/*/SKILL.md` | 28個の wrapper が対応する command markdown を Source of Truth として実行する | `skills/*/SKILL.md` 実体一覧 |
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
- agenda issue は `/work #N` から `/mtg` へ委譲される。hazard-candidate issue は `/work #N` が実装ルーティングをせず `/triage-issues-for-hazard` の実行を案内して終了する。根拠: `commands/work.md:83-96`, `commands/mtg.md:1-77`
- `/work`（および委譲先の `/task`）のゴールは ready PR の作成までであり、作成後の自律 review は行わない。根拠: `commands/git-pr.md:62-65`, `CLAUDE.md:15`
- PR review コメント対応は `/review-resolve #N`。根拠: `commands/review-resolve.md:1-6`
- review済みPRのdeliveryは `/git-pr-merge #N`。standaloneではcurrent headの明示承認を求め、`/task-manager`はcomplete delegated approval contextを渡す。根拠: `commands/git-pr-merge.md:1-37`, `commands/task-manager.md:247-296`
- 1〜3 issueのbatch実装は `/task-manager`。issue選定やmerge順最適化をせず、user-provided orderを実行する。根拠: `commands/task-manager.md:1-51`, `commands/task-manager.md:396-412`
- idea から issue を作る任意入口は `/new-issue`。根拠: `commands/new-issue.md:1-9`
- open issue を整理する任意入口は `/triage-issues`。根拠: `commands/triage-issues.md:1-9`
- auto-approve と access のログから source 固有のハザード候補を洗い出し、ユーザー一括承認後に `hazard-candidate` issue を起票する任意入口は `/analyze-hazard-scan`。hook自体は変更しない。根拠: `commands/analyze-hazard-scan.md:1-171`
- `hazard-candidate` issue の source 固有のハザード分析を開示し、実装着手を人間の承認ゲート越しに `/work #N` へ案内する任意入口は `/triage-issues-for-hazard`。yes 回答時のみ `hazard-candidate` → `triage-approved` の label 付け替えを行い（`/work` 側の gate を解除する）、それ以外は変更しない。`/work` は自身で呼ばない。根拠: `commands/triage-issues-for-hazard.md:1-115`
- `/docs-sync` が L0 昇格候補ありを案内した場合の任意入口は `/concept-maker`。L0（`docs/L0_concept/`）への唯一の AI 書き込み経路（`/init-docs` の初回新規作成を除く）。根拠: `commands/concept-maker.md:1-92`
- VitePress site の CI entry は `.github/workflows/deploy.yml` の `npm run docs:build`。根拠: `.github/workflows/deploy.yml:31-37`
- アプリケーション runtime の `main.*` / `server.*` / `app.*` は存在しない。実行入口は Markdown commands、shell installers/tests、VitePress npm scripts、GitHub Actions である。根拠: `rg --files -uu -g '!.git/**'`、`site/package.json:4-8`、`.github/workflows/deploy.yml:17-52`

## Workflow authority と責務分担

この repository は、workflow の開始権限と内部処理の責務を区別する。これは command か skill かという UI の違いではなく、誰がいつ workflow を開始できるかを明確にするための architecture である。

| 分類 | 役割 | 現行の例 |
|---|---|---|
| user-controlled workflow | ユーザーの明示意図で開始し、方向性・承認を伴う入口 | `/work`, `/work-multi`, `/task-manager`, `/mtg`, `/new-issue`, `/review-resolve`, issue triage / analysis workflows |
| internal workflow / stage | 上位 workflow が定めた順序で委譲する処理 | `/task`, `/patch`, `/docs-sync`, `/git-commit`, `/git-pr` |
| supporting capability / policy | active workflow が対象技術や状況に応じて適用する知識・規約 | `coding-*` commands と skills、hooks、templates |

Codex では各 workflow を skill wrapper で公開するが、workflow definition は対応する `commands/*.md` に一元化している。wrapper は現行 workflow を再解釈せず読み込む adapter であり、user-controlled workflow の開始権限を agent の自発的選択へ移すものではない。

根拠: `commands/README.md`, `skills/README.md`, `skills/work/SKILL.md:1-22`, `skills/task-manager/SKILL.md:1-29`

## 依存関係

`site/package.json` は本番依存として `@fortawesome/fontawesome-free`、開発依存として `vitepress` を宣言する。lock file から `@fortawesome/fontawesome-free` は 6.7.2、`vitepress` は 1.6.4 が解決されている。

根拠: `site/package.json:9-14`, `site/package-lock.json:765-766`, `site/package-lock.json:2486-2487`

## 未確認事項

現時点で docs に混在させた未確認事項はない。
