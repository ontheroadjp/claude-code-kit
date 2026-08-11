# Specification Summary

## 対象

このサマリは、`commands/`、`skills/`、`hooks/`、`templates/`、`site/`、CI の現在の実体を、確認できた範囲で整理する。

根拠: `rg --files -uu -g '!.git/**'`, `docs/.ai/repo.profile.json`

## Command Specifications

### `/work` (`commands/work.md`)

全作業の通常入口。G-0 はまず `git rev-parse --show-toplevel` が `.claude/worktrees/` 配下かを判定し、配下であれば（`EnterWorktree` が作成した worktree 内、例: `/work-multi`）main は主 worktree で既にチェックアウト済みのため `git checkout main` をスキップする。配下でなければ従来どおり `git checkout main` を実行する（session-approved には触れない。Stop hook が正常であれば既に absent であり、Step 2 の初回承認書き込みが自然に承認される）。その後 repo profile と workspace を確認する。issue 番号がある場合は現状調査より先に labels を取得する。

exact `report` label があれば `commands/report-review.md` へ委譲して実装せず終了する。`report` に該当せず exact `auto-approve-candidate` label があれば、`/triage-issues-for-auto-approve` の実行を促して終了する（issue #298）。どちらにも該当しない場合は issue 起点か、次に docs 変更が必要かで task / patch を判定する。この (A)/(B) ルーティングの判定基準は、現在ブランチが `main` 自身、または `EnterWorktree` が作る固定 prefix `worktree-` で始まる場合のみ (A) 新規作業とし、それ以外の全ての非 main ブランチは (B) 再開・エスカレーション（既存の未コミット変更有無・commits ahead 有無の判定）として扱う（issue #296、PR #304 レビューで修正。当初は `/task`・`/patch` の命名規則ベースで判定していたが、命名規則に沿わない既存ブランチ上の未コミット変更を誤って (A) 新規作業扱いする不具合が指摘された）。

非 main ブランチからの再開（case B scenario 2: コミットあり・ワークスペースクリーン）では、Phase 2 直接開始ではなく Phase 1 Step 2 から開始し session-approved を再作成する。

根拠: `commands/work.md:9-58`, `commands/work.md:78-152`

### `/work-multi` (`commands/work-multi.md`)

`/work` と全く同じワークフローを `EnterWorktree` 隔離下の専用 worktree 内で実行する、意図的な並行セッション利用向けの明示的 opt-in 入口（issue #296）。Step 0 で現在の作業ディレクトリを記録し、`EnterWorktree`（`path` 指定なし、常に新規 worktree）で切り替えた後、`scripts/link-worktree-untracked.sh` で元の working tree の untracked/ignored ファイル・ディレクトリ（`.git`・`.claude` を除く）を symlink する。この symlink群は `.gitignore` のディレクトリ限定パターンに一致せず `git status` に `??`/`!!` として現れるため、`scripts/link-worktree-untracked.sh` が書き出す manifest（`worktree-untracked-symlinks.txt`）を後続の `commands/work.md` G-2・`commands/task.md` Phase 2 が突き合わせる（issue #318）。Step 1 で `commands/work.md` を Read し一字一句そのまま実行する（ゲート・ルーティングロジックは重複定義しない）。

根拠: `commands/work-multi.md:1-52`

### `/report-review` (`commands/report-review.md`)

`report` label の issue 専用 read-only workflow。issue context と必要な repository evidence を読み、Facts、Assessment、Opinions、Proposals、Risks and Unknowns を分離して標準出力に提示する。ファイル、Git state、GitHub issue / PR を変更せず、実装 workflow へ委譲しない。

根拠: `commands/report-review.md:1-91`

### `/analyze-access` (`commands/analyze-access.md`)

`logs/access/*.log` を `scripts/analyze_access.py` で集計し、その JSON のみを根拠に KPIダッシュボード（Primary KPI: 重複読み込みによる推定ロス率 `redundant_access_waste.estimated_waste_ratio_pct`）→ Key Findings & Proposals → Evidence（裏付けデータ）→ Risks and Unknowns の順で構成したレポートを提示する read-only workflow。生ログは直接 Read しない。唯一の書き込みは `logs/reports/access/` 配下への新規 HTML レポートである。重複アクセス上位ファイル（`top_duplicate_files`）は発生元 phase/command 別の内訳（`by_phase`）を持ち、Key Findings ではこれを用いて重複クラスタの主因となる phase/command を明示的に特定する（issue #308）。

根拠: `commands/analyze-access.md:1-85`

### `/analyze-auto-approve` (`commands/analyze-auto-approve.md`)

`logs/auto-approve/*.log` を `scripts/analyze_auto_approve.py` で集計し、KPIダッシュボード（Primary KPI: 全体の自動承認率 `result_ratio_pct.approved`、および `/work` パイプラインの定型処理（git/gh write系操作）のユーザー確認率 `routine_ops.result_ratio_pct.user_prompt`）→ Key Findings & Proposals → Evidence → Risks and Unknowns の順で構成したレポートを提示する read-only workflow。`routine_ops` は `hooks/auto-approve-readonly.sh` の `check_session_approved()` が認識する git/gh write系コマンド形状で分類し、まだ user_prompt に落ちている定型処理パターンを列挙する。各パターンには、実際に user_prompt に落ちたコマンド文字列サンプル（`sample_commands`）も含まれる。`hooks/auto-approve-readonly.sh` 自体は変更せず、改善案は Proposals として提示するに留める。唯一の書き込みは `logs/reports/auto-approve/` 配下への新規 HTML レポートである。

根拠: `commands/analyze-auto-approve.md:1-93`

### `/analyze-token-usage` (`commands/analyze-token-usage.md`)

`logs/token-usage/*.log` を `scripts/analyze_token_usage.py` で集計し、KPIダッシュボード（Primary KPI: セッション横断の平均キャッシュ効率 `avg_cache_ratio`）→ Key Findings & Proposals → Evidence → Risks and Unknowns の順で構成したレポートを提示する read-only workflow。同ログはセッションごとに累積値が毎ターン追記される形式のため、スクリプト側でセッションIDごとの最終行のみを集計に用いる。唯一の書き込みは `logs/reports/token-usage/` 配下への新規 HTML レポートである。

根拠: `commands/analyze-token-usage.md:1-90`

### `/task` (`commands/task.md`)

`/work` から呼ばれる docs 変更を伴う実装 flow。issue がなければプラン策定とユーザー許可を先に行い、承認後に `commands/new-issue.md` Step 4-5 を使ってユーザー確認なしで issue を自動作成する（Step 1-3 の対話はスキップし、確定済みプランの内容で各セクションを埋める）。Step 1 では変更対象ファイルが確定した後に対応する L3 per-file doc（`docs/L3_implementation/<source-path>.md`）が存在する場合は必ず Read する。Step 2 では L3 per-file doc のパスを session-approved に含める。実装後・`/git-commit` 前に変更した各ソースファイルの L3 per-file doc を作成または更新し（現状スナップショット + 設計意図、changelog ではない）、`/git-commit` で commit する。Phase 2 では PR 本文・タイトルを SESSION_TMP_DIR（`/tmp/claude-code-kit/<session-id>/`）の `pr-body.md` / `pr-title.txt` に書き出し、`/docs-sync` → `/git-pr` を順に自動実行する（push・PR 作成は `/git-pr` が担う）。`docs/*` の変更は原則行わないが、L3 per-file doc（`docs/L3_implementation/<source-path>.md`）は実装フローの一部として例外的に task が管理する。PR 本文の `Specific docs sections to update` フィールドには、Phase 1 の投資調査で既に確認済みの specification_summary.md セクションの行範囲を citation として書き込み、`/docs-sync` へ引き継ぐ（issue #307）。

根拠: `commands/task.md:1-15`, `commands/task.md:50-66`, `commands/task.md:94-95`, `commands/task.md:139-170`, `commands/task.md:182`, issue #307

### `/patch` (`commands/patch.md`)

`/work` から呼ばれる docs 変更不要の軽微修正 flow。Step 1 では変更対象ファイルが確定した後に対応する L3 per-file doc（`docs/L3_implementation/<source-path>.md`）が存在する場合は Read する（L3 per-file doc は作成しない — docs 変更が必要になった場合は task フローへエスカレーションする）。プラン確認後に `patch/<slug>` branch で変更・commit し、ユーザーへ fast-forward merge 手順を報告する。前提が崩れた場合は issue draft を作り task flow へ移行する。

根拠: `commands/patch.md:1-90`, `commands/patch.md:15-26`

### `/docs-sync` (`commands/docs-sync.md`)

PR branch 上で `git diff main...HEAD` を事実として docs と README を最小更新する。G-4（PR 存在確認）は廃止。補助情報は GitHub PR body の代わりに SESSION_TMP_DIR の `pr-body.md` から取得する（存在しない場合は git diff のみで判断）。HARD STOP 時は `/init-docs` の documentation-only mode を自動実行し、包括的な再構築が完了したら commit・`pr-docs-sync-result.md` 書き出しへ復帰して呼び出し元へ通常完了として返す。push・PR 作成は行わない（`/git-pr` が担う）。L0（`docs/L0_concept/`）には一切書き込まず、L0 相当の記述を検知した場合は `docs/.ai/l0_candidates.md` へ候補を積んで `/concept-maker` の実行を案内するに留める（issue #273）。4 フェーズ構成（Phase 4 は最終報告）。

Phase 3 では docs・README.md 更新に加え、L3 per-file doc の変更履歴セクションを自動更新する。`git diff --name-only` で取得したソースファイル（`docs/` 配下を除く）に対応する `docs/L3_implementation/<path>.md` が存在する場合、`git log --oneline -10 -- <file>` を実行し `## 変更履歴（git log より自動生成）` セクションを更新または末尾追加する。L3 doc が存在しないファイルはスキップ（L3 doc 新規作成は `/task` が担う）。

Phase 1 Step 2 で pr-body.md の `Specific docs sections to update` から specification_summary.md の citation を取得済みの場合、Phase 2 でその行範囲を `offset`/`limit` で対象読みして再利用し、独自の再特定を行わない（citation がない場合は既存どおり独自探索する。issue #307）。

根拠: `commands/docs-sync.md:1-228`, `commands/docs-sync.md:48`, `commands/docs-sync.md:99-100`, issue #307

### `/init-docs` (`commands/init-docs.md`)

モード指定がなければ standalone mode とし、G-2 で `docs/init-docs-<YYYYMMDD>` 作業ブランチを作成または切り替える。そのブランチ上で repo 再観測、local tooling 観測、`docs/.ai/repo.profile.json` 生成、L1-L3 docs 生成、整合性検証、README scaffold 確認、CLAUDE.md / AGENTS.md 更新を行い、Phase 7 でユーザー確認後に個別 `git add` でステージしたうえで `/git-commit`（`fixed_message` 指定）による commit と draft PR を作成する（issue #300）。documentation-only mode が明示された場合は現在ブランチを維持して Phase 1〜6 だけを実行し、commit・push・PR 作成を行わず呼び出し元へ返る。L0（`docs/L0_concept/`）は存在しない場合のみ新規生成し、既に存在する場合は再実行時も一切変更しない（issue #273）。

local tooling 観測では `gh`、`node`、`npm`、Node.js runtime manager hints を確認し、環境依存の注意を command workflow ではなく `CLAUDE.md` の `Local Tooling Environment` に出力する。`AGENTS.md` は原則として `CLAUDE.md` への symlink とし、Codex CLI も同じ AI 運用情報を読む。

根拠: `commands/init-docs.md:33-47`, `commands/init-docs.md:153-168`, `commands/init-docs.md:306-322`, `commands/init-docs.md:353-372`, `commands/init-docs.md:377-403`

### `/concept-maker` (`commands/concept-maker.md`)

`/docs-sync` が `docs/.ai/l0_candidates.md` に積んだ L0 昇格候補を処理するスタンドアロン入口。候補ごとにソース文脈を確認し、`concept.md`/`policy.md` のどちらに追記すべきかを提示した上で、ドラフト提示 → ユーザー修正 → 再提示を繰り返し、明示的な承認を得てから追記する（機械的な一括生成はしない）。承認された候補は `concept/<YYYYMMDD>` branch 上で commit され、issue・PR は作らずユーザーが ff-merge する（`/patch` と同じ完結パターン）。`docs/L0_concept/` への AI 書き込みは `/init-docs` の初回新規作成とこの経路のみに限定される。

根拠: `commands/concept-maker.md:1-92`

### `/auto-approve-hazard-scan` (`commands/auto-approve-hazard-scan.md`)

`logs/auto-approve/*.log` で `user_prompt` に落ちている定型処理コマンドから allowlist 拡張候補を洗い出し、`hooks/auto-approve-readonly.sh --explain` の判定根拠をもとに AI が構造化ハザードチェックリストを作成し、既知ハザードが見つからない候補についてのみ `auto-approve-candidate` label 付き issue を起票するスタンドアロン入口（issue #284、#282 の一部）。`python3 scripts/analyze_auto_approve.py --all` の `routine_ops.patterns_needing_approval`（`sample_commands` 上位3件）を候補とし、既存 `auto-approve-candidate` issue との本文完全一致で重複除外した後、各候補について `--explain` を実行する。`--explain` は呼び出しセッション自身の session-approved ファイルを fast path として参照するため、`CLAUDE_CODE_KIT_SESSION_APPROVED_FILE` を存在しないパスへ向けて実行し、常に「新規セッションでの判定」を診断する。ハザードチェックリストは variable expansion / absolute-path・cwd bypass / unquoted write redirect / destructive flags / 既存 allow-shape との比較の5項目固定で、`already-safe`（ログ記録時点以降に既に allow-shape 拡張済み）/ `no-known-hazard`（issue化候補）/ `hazard-found`（issue化しない）の3種類に判定する。全候補を1回でまとめて提示し、`no-known-hazard` 候補への issue 起票はユーザーの一括承認後にのみ行う。`hooks/auto-approve-readonly.sh` を含む既存コードは一切変更しない。

根拠: `commands/auto-approve-hazard-scan.md:1-162`

### `/triage-issues-for-auto-approve` (`commands/triage-issues-for-auto-approve.md`)

`/auto-approve-hazard-scan`（issue #284）が起票した `auto-approve-candidate` label 付き open issue を一覧化し、issue ごとに AI ハザード分析を開示した上で実装に進むかどうかをユーザーに確認するスタンドアロン入口（issue #285、#282 の一部）。`gh issue list --label auto-approve-candidate --state open` で候補を取得し、issue 本文を `## Overview` / `## Evidence` / `## --explain Output` / `## Hazard Checklist` / `## Proposed Change (not implemented here)` の固定セクション見出しで分割してそのまま転記し提示する（要約・言い換えはしない）。見出しが見つからない issue は本文全体をそのまま提示するフォールバックを持つ。承認は issue 単位の yes/no で、yes の場合は `auto-approve-candidate` → `triage-approved` へ label を swap した上で（`triage-approved` 未存在時はユーザー確認の上で新規作成）、`/work` を自身で起動せず「`/work #N` を実行してください」と案内するのみに留める（issue #298）。label 付け替え以外の `gh issue` の本文編集・close・comment、および `hooks/auto-approve-readonly.sh` を含む既存コードの変更は一切行わない。`commands/triage-issues.md`（issue 衛生全般のトリアージ）とは判断基準が異なるため別ファイルとして維持し、`commands/triage-issues.md` 自体は変更しない。

根拠: `commands/triage-issues-for-auto-approve.md:1-116`

### `/triage-issues` (`commands/triage-issues.md`)

open issue が溜まったタイミングで実行するスタンドアロンのトリアージ入口。`gh issue list` で全 open issue を取得し、`docs/.ai/repo.profile.json` および `docs/L3_implementation/specification_summary.md` と照合して stale / inconsistent / duplicated / unclear / ready の 5 カテゴリに分類する。分類結果をユーザーに提示し、issue ごとに推奨アクション（close / comment / edit / label / skip）を「理由 + 推奨アクション」付きで提示してユーザー承認後のみ実行する。`/work`・`/task`・`/new-issue`・`/review-resolve` とは独立しており、既存コマンドの振る舞いは変更しない。

根拠: `commands/triage-issues.md:1-178`

### `/new-issue` (`commands/new-issue.md`)

実装を伴わず、rough idea から issue draft を作成して `gh issue create` する任意 pre-`/work` flow。scope 分割方針（分割しない／Phase分割／親子issue分割／単体分割）はユーザー選択必須で、親子issue分割を選んだ場合は子issueを先に作成し、GitHub の task list 機能（`- [ ] #<子issue番号>`）で親issueに進捗を自動連動させる。issue 本文は実行 agent に応じて `~/.claude/templates/issue.md` または `~/.codex/templates/issue.md` を使う。

根拠: `commands/new-issue.md:1-146`

### `/review-resolve` (`commands/review-resolve.md`)

PR 番号を受け取り、`tool:git_write` の session-approved ゲート（task.md/patch.md と同じ仕組み。git write のみが対象で `gh api` 経由のコメント返信は対象外）を1度だけ確認したうえで PR branch に checkout し、inline review comment・CHANGES_REQUESTED/COMMENTED/APPROVED 状態の review body comment を取得する。いずれも存在しない場合は「レビューコメントはありません」と報告して終了する。コメントごとにユーザーが対応・反対返信・理由返信・skip を選び、対応する場合は実装・commit・push・返信まで行う。

根拠: `commands/review-resolve.md:1-199`

### `/codex-review` (`commands/codex-review.md`)

PR 番号を受け取り、PR ブランチに checkout し、事前に `git diff origin/<base>...HEAD` を取得し、`codex exec` に `--sandbox read-only` かつ標準入力（`<stdin>` ブロック）経由でその diff を渡してレビューを実行する。結果を一時ファイルに保存して ANSI コードを除去し、内容を判定して問題なし / 問題ありを決定する。`CODEX_REVIEW_TOKEN` 環境変数は必須で、未設定の場合は `~/.claude/settings.local.json` への設定方法を案内してエラー終了する。設定されている場合は `gh pr review --approve` または `--request-changes` を提出する。問題ありの場合は完了報告後に `/review-resolve #<PR番号>` を自動実行する。

根拠: `commands/codex-review.md:1-164`

### `/coding-*` (`commands/coding-*.md`)

`coding-general` はrepository固有の設定を優先する言語非依存原則を定義し、`coding-py`、`coding-js`、`coding-ts`、`coding-sh` が言語固有ルールを追加する。`coding-react` はJavaScript/TypeScript layerの後にpure render、Hook、state、Effect、identity、accessibility、behavior testのanti-patternを追加し、`coding-nextjs` はさらにserver/client boundary、認可、cache、rendering mode、routing、secret、mutationのanti-patternを追加する。Next.jsのversion依存semanticsは導入済みversionの一次情報で確認する。

根拠: `commands/coding-general.md:1-52`, `commands/coding-py.md:1-93`, `commands/coding-js.md:1-85`, `commands/coding-ts.md:1-129`, `commands/coding-sh.md:1-88`, `commands/coding-react.md:1-43`, `commands/coding-nextjs.md:1-43`

### `/git-commit` (`commands/git-commit.md`)

コミット作成手順を定義するスラッシュコマンド。WIP commits の正規化（HEAD が `wip:` の場合のみ、最近の non-WIP commit まで遡り `git reset --soft` で staging area に展開。non-WIP commits には一切触れない）、staged diff 取得、個人情報等のチェック、Conventional Commits message 作成、commit 実行を定義する。`task.md`・`patch.md`・`review-resolve.md`・`docs-sync.md` から `/git-commit` として呼び出される。

根拠: `commands/git-commit.md:1-109`

### `/git-pr` (`commands/git-pr.md`)

`git push` と `gh pr create` を担うスラッシュコマンド。`/task` Phase 2 から `/docs-sync` 完了後に自動呼び出しされる。SESSION_TMP_DIR（`/tmp/claude-code-kit/<session-id>/`）の `pr-title.txt`（タイトル）・`pr-body.md`（本文）・`pr-docs-sync-result.md`（docs sync 結果）を参照し、存在しない場合は git diff / テンプレートから生成する。PR は ready for review として直接作成し、Step 7 の URL 報告でフローは完結する（作成後の自動 review・merge は行わない）。

根拠: `commands/git-pr.md:1-66`

## Skills

`skills/*/SKILL.md` は Codex 用の wrapper で、対応する `commands/*.md` を Source of Truth として読む。framework layerはgeneral → JavaScript → TypeScript → React → Next.jsの依存順を明示する。現存するskill wrapperは26件でcommandsと対応する。`report-review` skillおよび`analyze-access` / `analyze-auto-approve` / `analyze-token-usage` skillはread-only境界を保持する。

根拠: `skills/init-docs/SKILL.md:1-14`, `skills/report-review/SKILL.md`, `skills/` 実体一覧

## Hooks

### `hooks/auto-approve-readonly.sh`

PreToolUse hook。Read、session temp / session-listed file、read-only Bash、`git add`/`git commit -m`/`git fetch`/`git checkout main`・`git switch main` の narrow な allow-shape（ローカルリポジトリ外に影響しないため session-approved 不要）、session-approved tool category を自動承認する。Write / Edit / apply_patch は working repo（Claude/Codex 起動時の PWD が属する git リポジトリ）内であれば WIP commit 後に承認する動的防御を持つ。Bash は quoted-delimiter heredoc body をプレースホルダーに置換した上で、session-approved fast path → repo 内 rm -rf 動的防御 → `rm [-f] <literal-path>`（保護対象パス`is_rm_protected_path`を除く repo 内のみ。session-approved ファイル自身は保護対象のため対象外、issue #250）の自動承認 → destructive guard → write redirect → quote-aware segment 分割 → read-only 判定の順で評価し、分類不能な構文や write mode は通常許可フローへ戻す。`$()` は中身を再帰的に `is_safe_segment` で検証し、全て read-only であれば承認する（backtick と `<()` は常時ブロック）。詳細な許可順序・対象・除外条件は[auto-approve-readonly hook specification](https://github.com/ontheroadjp/core-toolkit-for-claude/blob/main/docs/L3_implementation/hooks/auto_approve_readonly.md)を参照する。decision log は `agent=claude|codex` と `session=<id|n/a>`、および hook 自身の実行時間 `duration_ms=<ms|NA>`（`$EPOCHREALTIME` 計測。bash 5.0 未満では `NA`）を含む。デバッグ専用の `--explain "<command>"` エントリポイント（issue #283）があり、通常の PreToolUse 判定パスとは独立して stdin を読まずに動作し、実際の判定関数（`is_safe_<name>_command` 群、`check_session_approved` 等）を再利用しながらコマンドがどのセグメントに分割されどう判定されるかを報告する（副作用なし）。

`sed` の `e` / `w`、external command を pipe する `awk getline`、`awk` の `print`/`printf` 出力リダイレクト、file output 等を含む curl short-option cluster は read-only とみなさない。Git write category は shared predicate により `+refspec` push、forced checkout/switch、forced branch deletion を除外する。write redirect 検出は quote-aware（シングルクォート内の比較演算子としての `>` を誤検知しない）で、`>&<数値fd|->` は fd 複製として background operator 扱いしない。

セッション ID 解決は `hooks/lib/session-id.sh` を source して行う（`hooks/cleanup-session.sh` と共有）。優先順位は `CLAUDE_CODE_KIT_SESSION_ID` → `CLAUDE_CODE_SESSION_ID`（Claude Code のセッション ID env var） → payload の `session_id` → payload の `transcript_path` hash → `CODEX_THREAD_ID` hash → `process-<PPID>` fallback。承認ファイルの解決結果を通知するグローバル共有ポインタファイル（旧 `current-session-approved-path`）は issue #210 で廃止済み。

安全性が実行時変数に依存する危険操作（例: `rm -f "$VAR"`）は、hook がコマンドテキストを実行せずに値を検証できないため、read-only な解決ステップ → リテラル値埋め込みという2段階（resolve-then-embed、`CLAUDE.md` に規約化）に分けることをエージェントに求める。hook はリテラル引数のみを `is_rm_protected_path`/`is_in_working_repo` と照合する（issue #248, #250）。

根拠: `hooks/auto-approve-readonly.sh:1-2063`, `hooks/lib/approval-safety.sh:1-119`, `hooks/lib/session-id.sh:1-46`, `docs/L3_implementation/hooks/auto_approve_readonly.md`, `CLAUDE.md`

### `hooks/lib/approval-safety.sh`

PreToolUse hook で共有する Bash safety helper。system directory 破壊、block device 操作、fork bomb、history rewrite、force push、hard reset、checkout/restore dot、clean、forced branch deletion、stash drop/clear を破壊的操作として検出し、JSON block decision を生成する。Git force predicate は session-approved fast path と destructive guard で共有し、branch deletion は同一 shell segment 内の delete / force option だけを組み合わせる。

根拠: `hooks/lib/approval-safety.sh:1-119`, `docs/L3_implementation/hooks/lib/approval-safety.sh.md`

### `hooks/lib/session-id.sh`

`hooks/auto-approve-readonly.sh` と `hooks/cleanup-session.sh` が共有するセッション ID 解決 helper（`session_id_resolve`/`session_id_sanitize`/`session_id_hash_key`）。両ファイルに重複していたロジックを一本化した。`commands/*.md` は任意のユーザープロジェクトディレクトリで実行されるためこのファイルを `source` しない。以前は同じ解決式を各 `commands/*.md` にインライン展開していたが、この式自体（brace expansion・代入への command substitution）が `/work-multi` の worktree 隔離セッションで harness に拒否されていたため、現在は `hooks/lib/session-paths.sh` 経由で間接的に再利用する（issue #316）。

根拠: `hooks/lib/session-id.sh:1-46`, `docs/L3_implementation/hooks/lib/session-id.sh.md`

### `hooks/lib/session-paths.sh`

`commands/task.md`・`patch.md`・`review-resolve.md`・`docs-sync.md`・`git-pr.md`・`triage-issues-for-auto-approve.md` が `source` ではなく `bash ~/.claude/hooks/lib/session-paths.sh <session-approved|session-tmp-dir>`（Codex: `~/.codex/...`）として直接実行するセッションパス解決 CLI（issue #316）。内部で `session-id.sh` の `session_id_resolve` を再利用し、標準出力へ絶対パスを1行返す。`session-approved` モードは `hooks/cleanup-session.sh`/`hooks/auto-approve-readonly.sh` と同じ formula（`CLAUDE_CODE_KIT_SESSION_APPROVED_FILE` → `CLAUDE_CODE_KIT_SESSION_DIR` → `CLAUDE_CODE_KIT_STATE_HOME`/`XDG_STATE_HOME` の順にオーバーライドを尊重）で解決し、`session-tmp-dir` モードは `CLAUDE_CODE_KIT_TMP_ROOT`（既定 `/tmp/claude-code-kit`）配下の絶対パスを返す。`install.sh` が `hooks/lib/*.sh` を `~/.claude/hooks/lib/`・`~/.codex/hooks/lib/` へ symlink することで、`commands/*.md` からインストール済みパス経由で直接実行できる。

根拠: `hooks/lib/session-paths.sh:1-37`, `docs/L3_implementation/hooks/lib/session-paths.sh.md`, issue #316

### `hooks/guard-destructive-cmd.sh`

PreToolUse Bash guard の互換 wrapper。Bash 以外は何も出力せず終了する。Bash の場合は `hooks/lib/approval-safety.sh` を読み込み、破壊的操作に該当する場合のみ JSON block decision を返す。平文 stdout は出力しない。

根拠: `hooks/guard-destructive-cmd.sh:1-24`, `hooks/lib/approval-safety.sh:1-119`

### `hooks/cleanup-session.sh`

Stop hook。`hooks/lib/session-id.sh` を source してセッション ID を解決し、現在の hook セッションに対応する `session-approved` を削除し、空になった session directory のみ削除する。SESSION_TMP_DIR（`/tmp/claude-code-kit/<session-id>/`）は削除しない。Stop hook はターン終了ごとに発火するため、スキル間（`/task` → `/docs-sync` → `/git-pr`）で temp ファイルが消えてしまう問題を避けるためである。SESSION_TMP_DIR の保持期間と削除時期は host OS の `/tmp` policy に依存し、repository からは確定できない。

根拠: `hooks/cleanup-session.sh:1-24`

詳細（生成される中間ファイルと削除タイミング全体）: `docs/L3_implementation/intermediate-files.md`

### `hooks/tmux-agent-status.sh`

Standalone helper called by Claude Code / Codex hooks to display AI agent status as an emoji prefix on the current tmux window title. Takes one optional argument (🔵, 🔴, or ✅); when called with no argument, enters clear mode — strips the emoji prefix and renames the window to the clean name without adding a new emoji. Silently exits when `$TMUX` is unset (no-op outside tmux). Uses `$TMUX_PANE` when available to target the current pane's window, strips repeated known status prefixes before setting the new one, and treats `tmux rename-window` failure as a silent no-op. Registered as independent entries in `install.sh` via `add_claude_hook` / `add_codex_hook`.

Semantic mapping: `UserPromptSubmit` / `PreToolUse` / `PostToolUse` → 🔵 (executing or execution resuming), `Notification` → 🔴 (permission/input needed), `Stop` → ✅ (turn complete, ready for next input). `PreToolUse` and `PostToolUse` are included so permission/input acknowledgements that do not emit `UserPromptSubmit` can still return the tmux prefix to executing state. When the claude/codex process itself exits, the shell wrapper calls the script with no argument to clear the prefix entirely:
```bash
claude() { command claude "$@"; bash ~/.claude/hooks/tmux-agent-status.sh 2>/dev/null; }
codex()  { command codex  "$@"; bash ~/.claude/hooks/tmux-agent-status.sh 2>/dev/null; }
```

根拠: `hooks/tmux-agent-status.sh:1-35`, `install.sh:155-187`

### `hooks/notify-slack.sh`

Notification と Stop で Claude/Codex の hook 設定から呼ばれる Slack 通知 script。installer は top-level hooks の symlink と event registration を両環境へ追加する。

根拠: `hooks/notify-slack.sh`, `install.sh:33-45`, `install.sh:165-186`

### access / token log hooks

`log-access-prompt.sh`、`log-access-tool.sh`、`log-access-stop.sh` はユーザー指示、tool access、modified files を session file / pending file / monthly log に記録する。`log-token-usage.sh` は transcript usage を集計して token usage log に追記する。`log-access-stop.sh` と `log-token-usage.sh` は `hooks/lib/hook-timing.sh` を使って自身の実行時間も計測し、それぞれ `[Hook処理時間]` セクション（累積、カンマ区切り）と `duration_ms=<ms|NA>` フィールド（行単位）としてログへ記録する。`log-access-stop.sh` の重複アクセス検出は `.accesses[].phase`（`log-access-tool.sh` が付与）も集計軸に加え、`重複アクセス:` の各行に `[phase:count, ...]` の内訳を付与する（issue #308）。

根拠: `hooks/log-access-prompt.sh`, `hooks/log-access-tool.sh`, `hooks/log-access-stop.sh`, `hooks/log-token-usage.sh`, `hooks/lib/hook-timing.sh`

## Templates

`templates/issue.md` は issue draft、`templates/pr.md` は PR body、`templates/readme.md` は README scaffold の template である。実体は repository の `templates/` に保持し、`install.sh` が各ファイルを `~/.claude/templates/` と `~/.codex/templates/` へ symlink する。template を使う commands は実行 agent に応じた installed path を参照する。`templates/pr.md` の `Specific docs sections to update` フィールドは、`/task` の投資調査で解決済みの specification_summary.md citation（`file:line-range`）を運ぶ handoff チャネルとしても使われ、`/docs-sync` がこれを再利用する（issue #307）。

根拠: `templates/issue.md:1-25`, `templates/pr.md:1-32`, `install.sh:10-19`, `install.sh:56-63`, `commands/task.md:11-18`, `templates/pr.md:29`, issue #307

## Tests

`tests/hooks/test-approval-hooks.sh` は PreToolUse hook の shell verification である。破壊的 Bash block、session-approved があっても破壊的操作を block すること、read-only approval、session-approved approval、session temp boundary、working repo dynamic defense、quoted heredoc と nested subshell の走査、`guard-destructive-cmd.sh` の JSON block output を検証する。`rm [-f] <literal-path>` は repo 内 path を positive case、repo root・`.git`・変数・glob・session-approved 自身を negative case として固定する。さらに issue #261 の回帰防止として、absent な session-approved への初回実承認 write は通り、exists-empty から実内容への拡張は block される Write-handler state transition を固定する。

根拠: `tests/hooks/test-approval-hooks.sh:1-1163`

`tests/commands/test-report-review.sh` は exact report label routing、read-only boundary、標準出力 sections、Git/GitHub write command の不在、command/skill catalog の整合性を静的検証する。

根拠: `tests/commands/test-report-review.sh:1-73`

`tests/commands/test-coding-guidelines.sh` はReact/Next.js layerの依存順、代表anti-pattern、task/patch routing、およびcoding commandにlocal absolute pathやrepository名が混入しないことを静的検証する。

根拠: `tests/commands/test-coding-guidelines.sh:1-53`

`tests/install/test-install.sh` は isolated fixture HOME に installer を2回実行し、Claude Code と Codex CLI の両 template directory に repository source への個別 symlink が作られること、旧 target が作成されないこと、再実行が冪等であることを検証する。`hooks/lib/*.sh` が Claude/Codex 両 `hooks/lib/` target へ symlink されることも合わせて検証する（issue #316）。

根拠: `tests/install/test-install.sh:1-85`

`tests/hooks/test-session-paths.sh` は `hooks/lib/session-paths.sh`（issue #316）の functional test である。`session-approved`/`session-tmp-dir` 両モードの既定 formula、`CLAUDE_CODE_KIT_STATE_HOME`/`CLAUDE_CODE_KIT_SESSION_DIR`/`CLAUDE_CODE_KIT_SESSION_APPROVED_FILE`/`CLAUDE_CODE_KIT_TMP_ROOT` オーバーライドの優先順位、symlink 経由実行時の自己位置解決、不正引数時の異常終了を検証する。

根拠: `tests/hooks/test-session-paths.sh:1-87`

`tests/commands/test-work-multi.sh` は `commands/work-multi.md` が `EnterWorktree` 呼び出しと `commands/work.md` への委譲のみで構成されゲート定義を重複していないこと、`skills/work-multi/SKILL.md` の scope guard、`commands/work.md` の worktree パスガードと `worktree-` prefix ベースのブランチ分類、`scripts/link-worktree-untracked.sh` の実行権限と `.git`/`.claude` 除外を静的検証する（issue #296、PR #304）。

根拠: `tests/commands/test-work-multi.sh:1-83`

`tests/scripts/test-link-worktree-untracked.sh` は `scripts/link-worktree-untracked.sh` の symlink 挙動を functional に検証する。一時 git リポジトリを用意し、トップレベル untracked ファイル/ディレクトリ、tracked ディレクトリ配下にネストした untracked ディレクトリの symlink、`.git`/`.claude` の除外、再実行時の冪等性、および `hooks/lib/session-paths.sh` が解決可能な場合の manifest（`worktree-untracked-symlinks.txt`）書き出しを確認する（issue #296、issue #318）。

根拠: `tests/scripts/test-link-worktree-untracked.sh:1-126`

## Install and Status Line

`install.sh` は `commands/*.md` を `~/.claude/commands/` と `~/.codex/commands/`、`hooks/*.sh` を `~/.claude/hooks/` と `~/.codex/hooks/`、`hooks/lib/*.sh` を `~/.claude/hooks/lib/` と `~/.codex/hooks/lib/`（issue #316。`[ -e "$src" ] || continue` で空 glob 展開をスキップするガード付き）、`skills/*/` を `~/.codex/skills/`、`templates/*.md` を `~/.claude/templates/` と `~/.codex/templates/` に個別 symlink する。旧 `~/.config/claude-code-kit/templates` は作成も削除もしない。その後 `jq` があれば migration helper（`remove_claude_hook` / `remove_codex_hook`）で旧 hook entry を除去してから `add_claude_hook` / `add_codex_hook` で新 entry を追加する。idempotent な設計のため複数回実行しても重複しない。Codex hooks は `/hooks` で review/trust してから利用する前提で案内する。

`setup_statusline.sh` は `scripts/statusline.sh` を `~/.claude/statusline.sh` に symlink し、settings に `statusLine` を追加する。`scripts/statusline.sh` は stdin JSON から context / five-hour / seven-day rate limit を抽出して表示する。

根拠: `install.sh:12-208`, `setup_statusline.sh:6-55`, `scripts/statusline.sh:10-83`

`scripts/analyze_access.py` / `analyze_auto_approve.py` / `analyze_token_usage.py` は `logs/<type>/*.log` を月単位（`--month YYYY-MM` / `--all` / 省略時は最新月）でパースし、集計結果を JSON として標準出力へ出力する（対応する `/analyze-*` command から呼ばれる）。`scripts/lib/analyze_common.py` が対象月解決・ログ列挙・CLI引数定義・百分位計算（`percentile()`）を3スクリプト共通で提供する。`analyze_token_usage.py` は `logs/token-usage/*.log` がセッションごとの累積値である点を踏まえ、セッションIDごとの最終行のみを集計する。3スクリプトとも、対応する hook 自身の実行時間（`duration_ms`）を `duration_ms_stats` として集計する。

根拠: `scripts/analyze_access.py:1-6`, `scripts/analyze_auto_approve.py:1-6`, `scripts/analyze_token_usage.py:1-9`, `scripts/lib/analyze_common.py:1`

`scripts/link-worktree-untracked.sh` は `commands/work-multi.md` から呼ばれ、引数に取った元の working tree に対して `git status --porcelain -z --ignored=matching` の NUL 区切り出力から `??`/`!!` エントリを列挙し、`.git`・`.claude` とその配下を除く全てを現在の working tree（新しい worktree）の同一相対パスへ symlink する（issue #296、PR #304 レビューで `git clean -ndx` の人間向け出力パースから変更）。symlink 化したパスは `.gitignore` のディレクトリ限定パターンに一致せず `git status` に `??`/`!!` として現れるため、`hooks/lib/session-paths.sh` が解決可能な場合は symlink 化した相対パス一覧を session tmp directory 配下の `worktree-untracked-symlinks.txt` に書き出す。`commands/work.md` G-2・`commands/task.md` Phase 2 はこの manifest と突き合わせてから「差分があるか」を判定する（issue #318）。

根拠: `scripts/link-worktree-untracked.sh:1-59`

## VitePress Site and CI

`site/package.json` は `docs:dev`, `docs:build`, `docs:preview` を定義する。dependencies は `@fortawesome/fontawesome-free`、devDependencies は `vitepress`。lock file では `@fortawesome/fontawesome-free` 6.7.2 と `vitepress` 1.6.4 が解決される。

`site/.vitepress/config.mts` は VitePress の `locales` オプションで多言語対応（i18n）を定義する。`root`（英語 / en-US）、`ja`（日本語 / ja-JP）、`zh`（中国語簡体字 / zh-CN）の 3 ロケールを持ち、各ロケールに nav・sidebar・footer を個別に定義する。コンテンツは `site/`（英語）、`site/ja/`（日本語）、`site/zh/`（中国語）に配置される。日本語版の concept・policy・specification ページは `docs/L0_concept/` および `docs/L3_implementation/specification_summary.md` を `@include` で参照する。

`.github/workflows/deploy.yml` は main push と `workflow_dispatch` を trigger とし、Node.js 24 で `site/` に対して `npm ci` と `npm run docs:build` を実行し、`site/.vitepress/dist` を GitHub Pages に deploy する。

根拠: `site/package.json:1-14`, `site/package-lock.json:765-766`, `site/package-lock.json:2486-2487`, `site/.vitepress/config.mts:1-183`, `.github/workflows/deploy.yml:1-53`

## 未確認事項

現時点で仕様サマリに混在させた未確認事項はない。
