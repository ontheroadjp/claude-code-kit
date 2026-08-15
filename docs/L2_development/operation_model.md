# Operation Model

## 通常作業フロー

`/review-resolve` は PR review 専用、`/mtg` は agenda の対話専用である。実装は `/work` から開始する。`/work` は issue に `agenda` label があれば実装調査より先に `/mtg` へ委譲し、`hazard-candidate` label があれば審査を案内し、それ以外を task または patch へ進める。

根拠: `commands/work.md:7-149`

## ルーティング

issue 番号がある場合は最初に exact `agenda` label、次に exact `hazard-candidate` label を判定する。

- `agenda` label の issue: `commands/mtg.md` を Read し、人間主導の対話を進める。`/new-issue` はユーザー明示指示でのみ実行する。
- `agenda` に該当せず `hazard-candidate` label の issue: `/triage-issues-for-hazard` の実行を促し、`/work` を終了する。
- どちらの label にも該当しない issue: 次の実装 routing を行う。

- issue 起点、または docs 変更が必要な場合: `commands/task.md` を Read し task flow を実行する。
- issue なし、かつ docs 変更が不要な場合: `commands/patch.md` を Read し patch flow を実行する。

根拠: `commands/work.md:64-121`

## mtg flow

`mtg.md` は agenda issue を起点に、方向性、フェーズ、スコープ、保留を非線形に検討する。必要な詳細化では Facts / Assessment / Opinions / Proposals を用いるが、決定・issue 起案・close は人間が明示的に行う。

根拠: `commands/mtg.md:1-77`

## task flow

`task.md` は docs 変更を伴う実装専用で、issue 確認または自動生成、調査補完、プラン承認、実装、L3 per-file doc、commit、PR title/body 準備、`/docs-sync`、`/git-pr` へ進む。一般 docs は直接変更せず、L3 per-file doc だけを実装 snapshot として管理する。

根拠: `commands/task.md:1-15`, `commands/task.md:30-179`

## patch flow

`patch.md` は docs 変更を伴わない軽微な修正専用で、issue/PR を不要とする。作業ブランチ上で commit し、ユーザーが main へ fast-forward merge する。docs 変更やスコープ拡大が判明した場合は task flow にエスカレーションする。

根拠: `commands/patch.md:1-8`, `commands/patch.md:38-69`, `commands/patch.md:73-95`

## docs-sync flow

`docs-sync.md` は main 以外の branch で `git diff main...HEAD` を事実として HARD STOP を判定し、docs/README と既存 L3 per-file doc の変更履歴を最小更新・commit する。push と PR 作成は行わず、結果を session temp に書いて `/git-pr` へ渡す。`docs/L0_concept/` には一切書き込まず、L0 相当の記述を検知した場合は `docs/.ai/l0_candidates.md` に候補を積んで `/concept-maker` の実行を最終報告で案内するのみ。

根拠: `commands/docs-sync.md:1-11`, `commands/docs-sync.md:13-217`

## init-docs flow

`init-docs.md` は repo 再観測、local tooling 観測、repo profile 生成、L0-L3 docs 生成、整合性検証、README scaffold 確認、CLAUDE.md / AGENTS.md 更新を行い、最後にユーザー確認後だけ commit と draft PR 作成へ進む。`docs/L0_concept/`（concept.md, policy.md）は既に存在する場合、再実行時も一切変更しない（存在しない場合のみ新規作成する）。

local tooling 観測では `gh`、`node`、`npm`、Node.js runtime manager hints を確認し、環境依存の注意を `CLAUDE.md` に出力する。`AGENTS.md` は原則として `CLAUDE.md` への symlink として作成する。

根拠: `commands/init-docs.md:21-423`

## concept-maker flow

`concept-maker.md` は `/work` から独立したスタンドアロン入口で、`docs/.ai/l0_candidates.md` に溜まった L0 昇格候補を処理する。候補ごとにソース文脈を Read し、`concept.md`/`policy.md` のどちらに追記すべきかを提示した上で、ドラフト提示 → ユーザー修正 → 再提示を繰り返し、明示的な承認を得てから追記する。承認された候補は `concept/<YYYYMMDD>` branch 上で commit され、issue・PR は作らずユーザーが ff-merge する（`patch` flow と同じ完結パターン）。キューが空、または承認候補が 0 件の場合は該当 Step をスキップする。

L0 は `/init-docs`（初回新規作成のみ）とこの flow の 2 経路以外から一切書き込まれない。

根拠: `commands/concept-maker.md:1-92`

## review-resolve flow

`review-resolve.md` は PR 番号を受け取り、PR branch へ checkout し、inline comment と review body comment を取得し、コメントごとに対応・反対返信・理由返信・skip を選ぶ。対応時は commit/push/reply まで行う。

根拠: `commands/review-resolve.md:1-175`

## codex-review flow

`codex-review.md` は PR 番号を受け取り、PR branch へ checkout して `codex review --base origin/<baseRefName>` を実行する。レビュー結果を一時ファイルに保存し、`CODEX_REVIEW_TOKEN` が設定されている場合だけ `gh pr review --approve` または `--request-changes` を提出する。問題ありの場合は `/review-resolve #<PR番号>` を続けて実行する。

根拠: `commands/codex-review.md:1-155`

## triage-issues flow

`triage-issues.md` は open issue を取得し、repo profile と仕様サマリに照らして stale / inconsistent / duplicated / unclear / ready に分類する。close / comment / edit / label などの issue 操作はユーザー承認後のみ実行する。

根拠: `commands/triage-issues.md:1-178`

## analyze flows

`analyze-access.md`、`analyze-auto-approve.md`、`analyze-token-usage.md` は、それぞれ repository-local な月次ログを Python 集計 script で読み、KPI / Evidence / Key Findings / Proposals / Opinions / Risks and Unknowns と HTML report を生成する。対象月は `--month YYYY-MM`、全期間は `--all`、省略時は最新月である。

根拠: `commands/analyze-access.md:16-87`, `commands/analyze-auto-approve.md:17-92`, `commands/analyze-token-usage.md:16-92`, `scripts/lib/analyze_common.py:30-77`

## analyze-hazard-scan flow

`analyze-hazard-scan.md` は auto-approve と access のログを分析する。auto-approve 候補は `python3 scripts/analyze_auto_approve.py --all` の `routine_ops.patterns_needing_approval` から抽出し、cold-session の `hooks/auto-approve-readonly.sh --explain` と安全性チェックリストで診断する。access 候補は `python3 scripts/analyze_access.py --all` の重複 path・phase 内訳・推定損失を根拠に抽出し、コマンド承認ログではないため `--explain` を実行しない。いずれも source と候補 command/path により既存 issue と重複除外し、`no-known-hazard` の候補だけをユーザー一括承認後に `hazard-candidate` issue として起票する。hook自体は変更しない。

根拠: `commands/analyze-hazard-scan.md:1-171`

## triage-issues-for-hazard flow

`triage-issues-for-hazard.md` は `gh issue list --label hazard-candidate --state open` で候補を取得し、issue 本文の source 固有の Diagnostic Output と Hazard Checklist を開示する。候補が1件以上あれば session-approved に候補 issue 番号ごとの `tool:gh_issue_write:<N>` を書き込む。issue ごとに「実装に進みますか？（yes/no）」を確認し、yes の場合は `hazard-candidate` → `triage-approved` へ label を swap してから（未存在なら確認の上 `gh label create`）、`/work` を自身で起動せず「`/work #N` を実行してください」と案内する。no の場合、および `gh issue` 本文編集・close・comment は行わない。

根拠: `commands/triage-issues-for-hazard.md:1-115`

## ローカル・CI コマンド

| コマンド | 用途 | 根拠 |
|---|---|---|
| `./install.sh` | symlink、Claude/Codex hook settings、Codex status line 登録 | `install.sh:13-202` |
| `./scripts/setup_statusline_for_claude.sh` | Claude statusline symlink と settings 登録 | `scripts/setup_statusline_for_claude.sh:6-57` |
| `./scripts/setup_statusline_for_codex.sh` | Codex TUI status line の冪等設定 | `scripts/setup_statusline_for_codex.sh:6-93` |
| `cd site && npm ci` | CI と同じ lockfile-based install | `.github/workflows/deploy.yml:31-33` |
| `cd site && npm run docs:dev` | VitePress dev server | `site/package.json:4-8` |
| `cd site && npm run docs:build` | VitePress build。CI でも実行 | `site/package.json:4-8`, `.github/workflows/deploy.yml:35-37` |
| `cd site && npm run docs:preview` | built site preview | `site/package.json:4-8` |
| `python3 scripts/analyze_access.py --all` | access logs の全期間集計 | `commands/analyze-access.md:27-35` |
| `python3 scripts/analyze_auto_approve.py --all` | auto-approve logs の全期間集計 | `commands/analyze-auto-approve.md:28-36` |
| `python3 scripts/analyze_token_usage.py --all` | token-usage logs の全期間集計 | `commands/analyze-token-usage.md:27-35` |
| `bash tests/hooks/test-approval-hooks.sh` | hook safety contract | `tests/hooks/test-approval-hooks.sh` |
| `bash tests/commands/test-mtg.sh` | agenda / mtg workflow contract | `tests/commands/test-mtg.sh` |
| `bash tests/commands/test-coding-guidelines.sh` | coding guideline composition and portability contract | `tests/commands/test-coding-guidelines.sh` |
| `bash tests/install/test-install.sh` | Claude/Codex template symlink と installer idempotency contract | `tests/install/test-install.sh` |
| `bash tests/install/test-setup-statusline-for-codex.sh` | Codex config の追加・置換・設定維持・冪等性 contract | `tests/install/test-setup-statusline-for-codex.sh` |
| `python3 -m pytest tests/scripts/` | log analysis scripts の parse / aggregate / CLI contract | `tests/scripts/` |

## CI/CD

`.github/workflows/deploy.yml` は main push と manual dispatch で実行される。build job は Node.js 24 を setup し、`site/` で `npm ci` と `npm run docs:build` を実行し、`site/.vitepress/dist` を Pages artifact として upload する。deploy job は `actions/deploy-pages@v5` で GitHub Pages に deploy する。

根拠: `.github/workflows/deploy.yml:1-53`

詳細: `docs/L2_development/cicd.md`

## 未確認事項

shell tests は存在するが CI workflow からは実行されない。CI 上の自動検証は VitePress build のみである。根拠: `tests/` 実体一覧、`.github/workflows/deploy.yml:17-52`
