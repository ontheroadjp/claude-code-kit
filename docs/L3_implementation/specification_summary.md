# Specification Summary

## 対象

このサマリは、`commands/`、`skills/`、`hooks/`、`templates/`、`site/`、CI の現在の実体を、確認できた範囲で整理する。

根拠: `rg --files -uu -g '!.git/**'`, `docs/.ai/repo.profile.json`

## Command Specifications

### `/work` (`commands/work.md`)

全作業の通常入口。G-0 はまず `git rev-parse --show-toplevel` が `.claude/worktrees/` 配下かを判定し、配下であれば（`EnterWorktree` が作成した worktree 内、例: `/work-multi`）main は主 worktree で既にチェックアウト済みのため `git checkout main` をスキップする。配下でなければ従来どおり `git checkout main` を実行する（session-approved には触れない。Stop hook が正常であれば既に absent であり、Step 2 の初回承認書き込みが自然に承認される）。G-2 は agent 別に配布された `worktree-status.sh` を使う。通常実行では `git status --porcelain` と同じ結果を返し、隔離 worktree の current session manifest があるときだけ自己作成 symlink を自動除外する。その後 repo profile と workspace を確認する。issue 番号がある場合は現状調査より先に親子関係と labels を取得する。親 issue なら native `subIssues` と未完了 task list から子 issue を収集し、open かつ GitHub native `blockedBy` が全て `CLOSED` の最初の子 issue、または実行不能な理由を報告して終了する。子 issue の実装・`/task`・`/patch` への委譲は行わない。

exact `agenda` label があれば `commands/mtg.md` へ委譲して実装せず終了する。`agenda` に該当せず exact `hazard-candidate` label があれば、`/triage-issues-for-hazard` の実行を促して終了する。どちらにも該当しない場合は issue 起点か、次に docs 変更が必要かで task / patch を判定する。「現状調査（共通）」の間は Read/Grep/Glob/WebFetch/WebSearch/`gh` の読み取り専用呼び出しのみを許可し、Edit/Write（session-tmp・session-approved ファイルを除く）は task.md/patch.md の Step 2 プラン承認まで行わない。WebFetch・WebSearch は調査目的の読み取りに限定し、web 上の素材のダウンロード・取得や外部サービスへの書き込みなど現状変更を伴う操作は禁止する。これらの禁止事項に該当する操作が調査上どうしても必要な場合は、理由をユーザーに報告し実行可否の判断を仰ぐ（issue #358）。

非 main ブランチからの再開（case B scenario 2: コミットあり・ワークスペースクリーン）では、Phase 2 直接開始ではなく Phase 1 Step 2 から開始し session-approved を再作成する。

根拠: `commands/work.md:9-56`, `commands/work.md:60-63`, `commands/work.md:90-158`

### `/work-multi` (`commands/work-multi.md`)

`/work` と全く同じワークフローを `EnterWorktree` 隔離下の専用 worktree 内で実行する、意図的な並行セッション利用向けの明示的 opt-in 入口（issue #296）。Step 0 で現在の作業ディレクトリを `ORIGINAL_WORKDIR` として記録し、`EnterWorktree`（`path` 指定なし、常に新規 worktree）で切り替えた後、installer が agent 別に配布する lazy linker の `prepare` で元 working tree を current session に記録する。`ORIGINAL_WORKDIR` はこの初期化専用であり、切り替え後の Read・現状調査・Git 操作は共有 checkout へ移動せず隔離 worktree から行う。この段階では untracked/ignored path を link しない。必要になった path だけを `link <relative-path>` で作成し、manifest に記録する。lazy link した path は読み取り専用であり、単独・並行を問わず symlink 経由で書き換えてはならない。書き込みが必要な path は link 前に worktree 内へ独立して作成する。venv/.venv だけは `link` の対象外で、`venv <relative-path>` サブコマンドを使う（issue #374）。basename が `venv`・`.venv`・path が既存・`.gitignore` で ignore されていない、のいずれかに該当すると拒否し、通過した場合のみ `uv`（無ければ `python3 -m venv`）で symlink ではない実体の仮想環境を worktree 内に構築する。構築した venv/.venv は書き込み境界の対象外で自由に書き込んでよく、symlink と同じ manifest に記録されて `worktree-status.sh` の除外対象になる。`worktree-status.sh` はその manifest を使い、後続の `commands/work.md` G-2・`commands/task.md` Phase 2 から自己作成 symlink（および venv 実体）を自動除外する。manifest が空または不在なら通常 status を返すため、単体 `/work` の挙動は変わらない。親 issue の検出と次に実行すべき子 issue の報告・終了は `commands/work.md` に一元化し、`work-multi` は worktree 準備後に同ファイルを一字一句そのまま実行する（ゲート・ルーティングロジックは重複定義しない）。

根拠: `commands/work-multi.md:1-76`, `install.sh:12-13,24-25,77-83`, issue #374

### `/task-manager` (`commands/task-manager.md`)

ユーザー指定の1〜3 implementation issueを入力順に実行するbatch executor。4件以上、重複、不正形式、closed/blocked/management issue、既存作業はmutation前に拒否するが、issue選定、batch compatibility、conflict-risk、merge順最適化は行わない。親agentが全issue planを一括提示し、承認後にissueごとのisolated worktreeと実 `task-worker` sub-agentを最大3つ作る。workerは親modelを継承し、source/test実装、validation、commit/push、Draft PR、structured handoffまでを担当する。

親はcomplete Draft source PR setだけを提示し、PRごとのfull head SHA、scope/behavior、final validation planをbatch-wide approvalで固定する。source deliveryは入力順に `/git-pr-merge`へ完全なdelegated contextを渡し、latest-main refresh、current-head validation、conflict repair、Ready transition、squash mergeのstate machineをtask-manager内へ複製しない。unknown commitやmaterial changeは対象PRだけを再承認する。途中停止時は完了済みmergeをrollbackせず、completed/pending stateを報告する。

全source delivery後はmerged changed-file unionをAdded/Modified/Deleted/Renamedへ分類し、latest mainをtruthとしてL3 per-file docs、aggregate docs、README、test index、config、schema、public surfaceを同期する。documentation failureは `source complete / documentation incomplete` としてstandalone `/init-docs` recoveryを案内する。全merge確認後にissue completion commentを投稿し、comment failureはmanual follow-upとする。

根拠: `commands/task-manager.md:1-145`, `commands/task-manager.md:147-296`, `commands/task-manager.md:298-412`, issue #389

### `/mtg` (`commands/mtg.md`)

`agenda` label の issue を人間と AI が非線形に検討する workflow。開始時には issue 本文と全コメントを読み、必要に応じて Facts、Assessment、Opinions、Proposals を使うが、方向性・実装境界・close は人間だけが決定する。今回の mtg の終了をユーザーが明示した場合は、日付・開始時刻・終了時刻を含む議事録を issue に投稿する。この投稿は issue close と独立しており、`/new-issue` はユーザーの明示指示でのみ実行する。

根拠: `commands/mtg.md:1-85`

### `/analyze-access` (`commands/analyze-access.md`)

`logs/access/*.log` を `scripts/analyze_access.py` で集計し、その JSON のみを根拠に KPIダッシュボード（Primary KPI: 重複読み込みによる推定ロス率 `redundant_access_waste.estimated_waste_ratio_pct`）→ Key Findings & Proposals → Evidence（裏付けデータ）→ Risks and Unknowns の順で構成したレポートを提示する read-only workflow。生ログは直接 Read しない。唯一の書き込みは `logs/reports/access/` 配下への新規 HTML レポートである。重複アクセス上位ファイル（`top_duplicate_files`）は発生元 phase/command 別の内訳（`by_phase`）と絞り込み読みだった件数（`narrowed_count`）を持ち、Key Findings ではこれを用いて重複クラスタの主因となる phase/command を明示的に特定する（issue #308）。Supporting KPI に絞り込み読みの実施率 `narrowed_read_ratio_pct`（`CLAUDE.md`「絞り込み読み（citation-based narrowed read）の検証」原則が実践されているかの指標）も含む（issue #363）。

根拠: `commands/analyze-access.md:1-85`

### `/analyze-auto-approve` (`commands/analyze-auto-approve.md`)

`logs/auto-approve/*.log` を `scripts/analyze_auto_approve.py` で集計し、KPIダッシュボード（Primary KPI: 全体の自動承認率 `result_ratio_pct.approved`、および `/work` パイプラインの定型処理（git/gh write系操作）のユーザー確認率 `routine_ops.result_ratio_pct.user_prompt`）→ Key Findings & Proposals → Evidence → Risks and Unknowns の順で構成したレポートを提示する read-only workflow。`routine_ops` は `hooks/auto-approve-readonly.sh` の `check_session_approved()` が認識する git/gh write系コマンド形状で分類し、まだ user_prompt に落ちている定型処理パターンを列挙する。各パターンには、実際に user_prompt に落ちたコマンド文字列サンプル（`sample_commands`）も含まれる。`hooks/auto-approve-readonly.sh` 自体は変更せず、改善案は Proposals として提示するに留める。唯一の書き込みは `logs/reports/auto-approve/` 配下への新規 HTML レポートである。

根拠: `commands/analyze-auto-approve.md:1-93`

### `/analyze-token-usage` (`commands/analyze-token-usage.md`)

`logs/token-usage/*.log` を `scripts/analyze_token_usage.py` で集計し、KPIダッシュボード（Primary KPI: セッション横断の平均キャッシュ効率 `avg_cache_ratio`）→ Key Findings & Proposals → Evidence → Risks and Unknowns の順で構成したレポートを提示する read-only workflow。同ログはセッションごとに累積値が毎ターン追記される形式のため、スクリプト側でセッションIDごとの最終行のみを集計に用いる。唯一の書き込みは `logs/reports/token-usage/` 配下への新規 HTML レポートである。

根拠: `commands/analyze-token-usage.md:1-90`

### `/task` (`commands/task.md`)

`/work` から呼ばれる docs 変更を伴う実装 flow。issue がなければプラン策定とユーザー許可を先に行い、承認後に `commands/new-issue.md` Step 4-5 を使ってユーザー確認なしで issue を自動作成する（Step 1-3 の対話はスキップし、確定済みプランの内容で各セクションを埋める）。Step 1 では変更対象ファイルが確定した後に対応する L3 per-file doc（`docs/L3_implementation/<source-path>.md`）が存在する場合は必ず Read する。Step 2 では L3 per-file doc のパスを session-approved に含める。作業ブランチを作成または切り替えた直後は、Claude Code でのみ Git が返すブランチ名を `~/.claude/scripts/rename-thread.sh` に渡して会話スレッドを更新し、Codex CLI はこの操作をスキップする。更新に失敗しても実装を中断しない。実装後・`/git-commit` 前に変更した各ソースファイルの L3 per-file doc を作成または更新し（現状スナップショット + 設計意図、changelog ではない）、`/git-commit` で commit する。Phase 2 では PR 本文・タイトルを SESSION_TMP_DIR（`/tmp/claude-code-kit/<session-id>/`）の `pr-body.md` / `pr-title.txt` に書き出し、`/docs-sync` → `/git-pr` を順に自動実行する（push・PR 作成は `/git-pr` が担う）。`docs/*` の変更は原則行わないが、L3 per-file doc（`docs/L3_implementation/<source-path>.md`）は実装フローの一部として例外的に task が管理する。PR 本文の `Specific docs sections to update` フィールドには、Phase 1 の投資調査で既に確認済みの specification_summary.md セクションの行範囲を citation として書き込み、`/docs-sync` へ引き継ぐ（issue #307）。

根拠: `commands/task.md:1-15`, `commands/task.md:50-66`, `commands/task.md:94-95`, `commands/task.md:139-170`, `commands/task.md:182`, issue #307

### `/patch` (`commands/patch.md`)

`/work` から呼ばれる docs 変更不要の軽微修正 flow。Step 1 では変更対象ファイルが確定した後に対応する L3 per-file doc（`docs/L3_implementation/<source-path>.md`）が存在する場合は Read する（L3 per-file doc は作成しない — docs 変更が必要になった場合は task フローへエスカレーションする）。プラン確認後に `patch/<slug>` branch で変更・commit し、ブランチ切替直後に Claude Code でのみ Git が返すブランチ名を `~/.claude/scripts/rename-thread.sh` に渡して会話スレッドを更新する。Codex CLI はこの操作をスキップし、更新失敗は実装を中断させない。ユーザーへ fast-forward merge 手順を報告する。前提が崩れた場合は issue draft を作り task flow へ移行する。

根拠: `commands/patch.md:1-90`, `commands/patch.md:15-26`

### `/docs-sync` (`commands/docs-sync.md`)

PR branch 上で `git diff main...HEAD` を事実として docs と README を最小更新する。G-4（PR 存在確認）は廃止。補助情報は GitHub PR body の代わりに SESSION_TMP_DIR の `pr-body.md` から取得する（存在しない場合は git diff のみで判断）。HARD STOP 時は `/init-docs` の documentation-only mode を自動実行し、包括的な再構築が完了したら commit・`pr-docs-sync-result.md` 書き出しへ復帰して呼び出し元へ通常完了として返す。push・PR 作成は行わない（`/git-pr` が担う）。L0（`docs/L0_concept/`）には一切書き込まず、L0 相当の記述を検知した場合は `docs/.ai/l0_candidates.md` へ候補を積んで `/concept-maker` の実行を案内するに留める（issue #273）。4 フェーズ構成（Phase 4 は最終報告）。確認は、git diff と実装前にユーザーが承認した作業プランを読んでも文書化の意味・範囲に複数の妥当な選択肢が残る場合だけに求める。実装済みの振る舞いと承認済みプランから一意に定まる仕様サマリの要約は、既決事項の文章化として確認なしで反映する（issue #354）。

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

### `/analyze-hazard-scan` (`commands/analyze-hazard-scan.md`)

`logs/auto-approve/*.log` と `logs/access/*.log` を集計し、source 固有のハザード候補を作るスタンドアロン入口。auto-approve 候補は cold-session の `--explain` と安全性チェックを根拠にし、access 候補は重複 path・phase 内訳・推定損失を根拠にする。既知ハザードのない候補だけを一括承認後に `hazard-candidate` issue として起票する。hook は変更しない。

根拠: `commands/analyze-hazard-scan.md`

### `/triage-issues-for-hazard` (`commands/triage-issues-for-hazard.md`)

`hazard-candidate` label 付き open issue を source 固有の Diagnostic Output と Hazard Checklist を保ったまま開示し、issue ごとに実装可否を確認する。yes の場合は `hazard-candidate` → `triage-approved` へ label を swap し、`/work #N` を案内する。`/work` 自動起動や本文編集は行わない。

根拠: `commands/triage-issues-for-hazard.md`

### `/triage-issues` (`commands/triage-issues.md`)

open issue が溜まったタイミングで実行するスタンドアロンのトリアージ入口。`gh issue list` で全 open issue を取得し、`docs/.ai/repo.profile.json` および `docs/L3_implementation/specification_summary.md` と照合して stale / inconsistent / duplicated / unclear / ready の 5 カテゴリに分類する。分類結果をユーザーに提示し、issue ごとに推奨アクション（close / comment / edit / label / skip）を「理由 + 推奨アクション」付きで提示してユーザー承認後のみ実行する。`/work`・`/task`・`/new-issue`・`/review-resolve` とは独立しており、既存コマンドの振る舞いは変更しない。

根拠: `commands/triage-issues.md:1-178`

### `/new-issue` (`commands/new-issue.md`)

実装を伴わず、rough idea から issue draft を作成して `gh issue create` する任意 pre-`/work` flow。scope 分割方針（分割しない／Phase分割／親子issue分割／単体分割）はユーザー選択必須で、親子issue分割を選んだ場合は親issueを先に作成してから子issueを作成し、各子issueを GitHub の native sub-issue として紐付ける。親子関係は native sub-issue を唯一の source of truth とし、親本文の Markdown task list や子issueへの親参照コメントは使用しない。issue 本文は実行 agent に応じて `~/.claude/templates/issue.md` または `~/.codex/templates/issue.md` を使う。

Step 2 は個別の内容確認を求めず、Step 4 でドラフトとラベル（既存採用 or 新規提案）をまとめて一度に提示し、単一承認で「ドラフト内容」「ラベル（採用/新規作成）」「`gh issue create` の実行」を一括認可する（issue #301）。standalone 起動時は承認後に session-approved へ `tool:gh_issue_write`（新規ラベルが必要な場合は `tool:gh_label_write` も）を書き込み、以降のハーネス許可プロンプトを不要にする。`commands/task.md` が Step 4〜5 のみを呼び出す issue 自動生成経路では、task.md 自身のプラン承認・session-approved 書き込みと二重にならないよう、この単一承認・session-approved 書き込みをスキップする。

根拠: `commands/new-issue.md:1-172`, issue #301

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

コミット作成手順を定義するスラッシュコマンド。WIP commits の正規化では、HEAD が `wip:` の場合のみ first-parent 上の連続 WIP range の直前にある non-WIP commit へ `git reset --soft` し、差分を staging area に展開する。この完全な reset 形は approval hook が現在履歴と literal hash を照合して自動承認し、照合に失敗する reset は通常の許可フローに戻る。staged diff 取得、個人情報等のチェック、Conventional Commits message 作成、commit 実行も定義する。`task.md`・`patch.md`・`review-resolve.md`・`docs-sync.md` から `/git-commit` として呼び出される。

根拠: `commands/git-commit.md:1-109`

### `/git-pr` (`commands/git-pr.md`)

`git push` と `gh pr create` を担うスラッシュコマンド。`/task` Phase 2 から `/docs-sync` 完了後に自動呼び出しされる。SESSION_TMP_DIR（`/tmp/claude-code-kit/<session-id>/`）の `pr-title.txt`（タイトル）・`pr-body.md`（本文）・`pr-docs-sync-result.md`（docs sync 結果）を参照し、存在しない場合は git diff / テンプレートから生成する。PR は ready for review として直接作成し、Step 7 の URL 報告でフローは完結する（作成後の自動 review・merge は行わない）。

根拠: `commands/git-pr.md:1-66`

### `/git-pr-merge` (`commands/git-pr-merge.md`)

review済みの単一Draft/Ready PRをapproved head SHAで固定し、owned PR worktree上でlatest `origin/main`をnormal mergeし、current post-refresh headをCIまたはapproved local commandsで検証してexplicit squash mergeするworkflow。standaloneは表示したPR/headへの明示承認を求め、delegated invocationはPR番号、approved head、scope/behavior、validation plan、approval source、owned worktreeを必須とする。

active invocation自身がSHA・parent・目的・changed pathsを記録したlatest-main merge/approved repairだけをknown commitとし、それ以外のhead driftは対象PRだけを再承認する。local `main` workspaceはcheckout、edit、repair、commit、pushに使わず、worktreeがdirty/unavailable/ownership不明ならfallbackせず停止する。merge後はPR state、squash OID、latest-main包含、1-commit resultを再取得して検証する。cleanupはcaller責務である。

根拠: `commands/git-pr-merge.md:1-48`, `commands/git-pr-merge.md:50-111`, `commands/git-pr-merge.md:113-147`, issue #389

## Skills

`skills/*/SKILL.md` は Codex 用の wrapper で、対応する `commands/*.md` を Source of Truth として読む。`mtg` skill は `/new-issue` と close をユーザー明示指示に限定する。`task-manager` skillは実 `task-worker`、親model継承、`git-pr-merge` delegationを固定する。`git-pr-merge` skillはstandalone/delegated approvalの区別、approved head必須、local main fallback禁止、caller-owned cleanupを固定する。

根拠: `skills/init-docs/SKILL.md:1-14`, `skills/mtg/SKILL.md`, `skills/task-manager/SKILL.md:1-29`, `skills/git-pr-merge/SKILL.md:1-25`, `skills/` 実体一覧

## Hooks

### `hooks/auto-approve-readonly.sh`

Claude Code では PreToolUse、Codex CLI では PermissionRequest で動く共有 auto-approve hook。Read、session temp / session-listed file、read-only Bash、`git add`/`git commit -m`/`git fetch`/`git checkout main`・`git switch main` の narrow な allow-shape、履歴照合済みの WIP squash `git reset --soft <literal hash>`、session-approved tool category を自動承認する。WIP squash reset は、HEAD の連続 WIP range と first-parent 上の直前 non-WIP commit が target hash と完全一致した場合だけ許可する。Codex の安全な操作には PermissionRequest 専用の `hookSpecificOutput.decision.behavior: allow` を返し、古い PreToolUse invocation には neutral fallback を返す。Claude の PreToolUse response は従来どおり `decision: approve` である。Write / Edit / apply_patch は working repo（Claude/Codex 起動時の PWD が属する git リポジトリ）内であれば WIP commit 後に承認する動的防御を持つ。Bash は quoted-delimiter heredoc body をプレースホルダーに置換した上で、session-approved fast path → repo 内 rm -rf 動的防御 → `rm [-f] <literal-path>`（保護対象パス`is_rm_protected_path`を除く repo 内のみ。session-approved ファイル自身は保護対象のため対象外、issue #250）の自動承認 → destructive guard → write redirect → quote-aware segment 分割 → read-only 判定の順で評価し、分類不能な構文や write mode は通常許可フローへ戻す。`$()` は中身を再帰的に `is_safe_segment` で検証し、全て read-only であれば承認する（backtick と `<()` は常時ブロック）。詳細な許可順序・対象・除外条件は[auto-approve-readonly hook specification](https://github.com/ontheroadjp/core-toolkit-for-claude/blob/main/docs/L3_implementation/hooks/auto_approve_readonly.md)を参照する。decision log は `agent=claude|codex` と `session=<id|n/a>`、および hook 自身の実行時間 `duration_ms=<ms|NA>`（`$EPOCHREALTIME` 計測。bash 5.0 未満では `NA`）を含む。デバッグ専用の `--explain "<command>"` エントリポイント（issue #283）があり、通常の hook 判定パスとは独立して stdin を読まずに動作し、実際の判定関数（`is_safe_<name>_command` 群、`check_session_approved` 等）を再利用しながらコマンドがどのセグメントに分割されどう判定されるかを報告する（副作用なし）。

`sed` の `e` / `w`、external command を pipe する `awk getline`、`awk` の `print`/`printf` 出力リダイレクト、file output 等を含む curl short-option cluster は read-only とみなさない。Git write category は shared predicate により `+refspec` push、forced checkout/switch、forced branch deletion を除外する。write redirect 検出は quote-aware（シングルクォート内の比較演算子としての `>` を誤検知しない）で、`>&<数値fd|->` は fd 複製として background operator 扱いしない。

セッション ID 解決は `hooks/lib/session-id.sh` を source して行う（`hooks/cleanup-session.sh` と共有）。優先順位は `CLAUDE_CODE_KIT_SESSION_ID` → `CLAUDE_CODE_SESSION_ID`（Claude Code のセッション ID env var） → payload の `session_id` → payload の `transcript_path` hash → `CODEX_THREAD_ID` hash → `process-<PPID>` fallback。承認ファイルの解決結果を通知するグローバル共有ポインタファイル（旧 `current-session-approved-path`）は issue #210 で廃止済み。

安全性が実行時変数に依存する危険操作（例: `rm -f "$VAR"`）は、hook がコマンドテキストを実行せずに値を検証できないため、read-only な解決ステップ → リテラル値埋め込みという2段階（resolve-then-embed、`CLAUDE.md` に規約化）に分けることをエージェントに求める。hook はリテラル引数のみを `is_rm_protected_path`/`is_in_working_repo` と照合する（issue #248, #250）。

根拠: `hooks/auto-approve-readonly.sh:1-2068`, `hooks/lib/approval-safety.sh:1-119`, `hooks/lib/session-id.sh:1-46`, `docs/L3_implementation/hooks/auto_approve_readonly.md`, `CLAUDE.md`

### `hooks/lib/approval-safety.sh`

PreToolUse hook で共有する Bash safety helper。system directory 破壊、block device 操作、fork bomb、history rewrite、force push、hard reset、checkout/restore dot、clean、forced branch deletion、stash drop/clear を破壊的操作として検出し、JSON block decision を生成する。Git force predicate は session-approved fast path と destructive guard で共有し、branch deletion は同一 shell segment 内の delete / force option だけを組み合わせる。

根拠: `hooks/lib/approval-safety.sh:1-119`, `docs/L3_implementation/hooks/lib/approval-safety.sh.md`

### `hooks/lib/session-id.sh`

`hooks/auto-approve-readonly.sh` と `hooks/cleanup-session.sh` が共有するセッション ID 解決 helper（`session_id_resolve`/`session_id_sanitize`/`session_id_hash_key`）。両ファイルに重複していたロジックを一本化した。`commands/*.md` は任意のユーザープロジェクトディレクトリで実行されるためこのファイルを `source` しない。以前は同じ解決式を各 `commands/*.md` にインライン展開していたが、この式自体（brace expansion・代入への command substitution）が `/work-multi` の worktree 隔離セッションで harness に拒否されていたため、現在は `hooks/lib/session-paths.sh` 経由で間接的に再利用する（issue #316）。

根拠: `hooks/lib/session-id.sh:1-46`, `docs/L3_implementation/hooks/lib/session-id.sh.md`

### `hooks/lib/session-paths.sh`

`commands/task.md`・`patch.md`・`review-resolve.md`・`docs-sync.md`・`git-pr.md`・`triage-issues-for-hazard.md` が `source` ではなく `bash ~/.claude/hooks/lib/session-paths.sh <session-approved|session-tmp-dir>`（Codex: `~/.codex/...`）として直接実行するセッションパス解決 CLI（issue #316）。内部で `session-id.sh` の `session_id_resolve` を再利用し、標準出力へ絶対パスを1行返す。`session-approved` モードは `hooks/cleanup-session.sh`/`hooks/auto-approve-readonly.sh` と同じ formula（`CLAUDE_CODE_KIT_SESSION_APPROVED_FILE` → `CLAUDE_CODE_KIT_SESSION_DIR` → `CLAUDE_CODE_KIT_STATE_HOME`/`XDG_STATE_HOME` の順にオーバーライドを尊重）で解決し、`session-tmp-dir` モードは `CLAUDE_CODE_KIT_TMP_ROOT`（既定 `/tmp/claude-code-kit`）配下の絶対パスを返す。`install.sh` が `hooks/lib/*.sh` を `~/.claude/hooks/lib/`・`~/.codex/hooks/lib/` へ symlink することで、`commands/*.md` からインストール済みパス経由で直接実行できる。

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

`log-access-prompt.sh`、`log-access-tool.sh`、`log-access-stop.sh` はユーザー指示、tool access、modified files を session file / pending file / monthly log に記録する。`log-token-usage.sh` は transcript usage を集計して token usage log に追記する。`log-access-stop.sh` と `log-token-usage.sh` は `hooks/lib/hook-timing.sh` を使って自身の実行時間も計測し、それぞれ `[Hook処理時間]` セクション（累積、カンマ区切り）と `duration_ms=<ms|NA>` フィールド（行単位）としてログへ記録する。`log-access-stop.sh` の重複アクセス検出は `.accesses[].phase`（`log-access-tool.sh` が付与）も集計軸に加え、`重複アクセス:` の各行に `[phase:count, ...]` の内訳を付与する（issue #308）。`log-access-tool.sh` は Read の `offset`/`limit` 使用有無も `.accesses[].narrowed` として付与し、`log-access-stop.sh` はこれを集計して `総アクセス数:` 行と `重複アクセス:` の各行に絞り込み読み件数のサフィックスを追加する（issue #363）。

根拠: `hooks/log-access-prompt.sh`, `hooks/log-access-tool.sh`, `hooks/log-access-stop.sh`, `hooks/log-token-usage.sh`, `hooks/lib/hook-timing.sh`

## Templates

`templates/issue.md` は issue draft、`templates/pr.md` は PR body、`templates/readme.md` は README scaffold の template である。実体は repository の `templates/` に保持し、`install.sh` が各ファイルを `~/.claude/templates/` と `~/.codex/templates/` へ symlink する。template を使う commands は実行 agent に応じた installed path を参照する。`templates/pr.md` の `Specific docs sections to update` フィールドは、`/task` の投資調査で解決済みの specification_summary.md citation（`file:line-range`）を運ぶ handoff チャネルとしても使われ、`/docs-sync` がこれを再利用する（issue #307）。

根拠: `templates/issue.md:1-25`, `templates/pr.md:1-32`, `install.sh:10-19`, `install.sh:56-63`, `commands/task.md:11-18`, `templates/pr.md:29`, issue #307

## Tests

`tests/hooks/test-approval-hooks.sh` は PreToolUse hook の shell verification である。破壊的 Bash block、session-approved があっても破壊的操作を block すること、read-only approval、session-approved approval、session temp boundary、working repo dynamic defense、quoted heredoc と nested subshell の走査、`guard-destructive-cmd.sh` の JSON block output を検証する。`rm [-f] <literal-path>` は repo 内 path を positive case、repo root・`.git`・変数・glob・session-approved 自身を negative case として固定する。さらに issue #261 の回帰防止として、absent な session-approved への初回実承認 write は通り、exists-empty から実内容への拡張は block される Write-handler state transition を固定する。

根拠: `tests/hooks/test-approval-hooks.sh:1-1385`

`tests/commands/test-mtg.sh` は exact agenda label routing、非線形の検討、明示指示だけでの `/new-issue`、ユーザー主導の close、command/skill contract を静的検証する。

根拠: `tests/commands/test-mtg.sh:1-57`

`tests/commands/test-coding-guidelines.sh` はReact/Next.js layerの依存順、代表anti-pattern、task/patch routing、およびcoding commandにlocal absolute pathやrepository名が混入しないことを静的検証する。

根拠: `tests/commands/test-coding-guidelines.sh:1-53`

`tests/commands/test-workflow-contracts.sh` は `/docs-sync`・`/init-docs`・`/task`・`/patch`・`/git-pr` の責務境界を静的検証する。`/docs-sync` が実装と承認済みプランから一意に定まる文書化を再確認せず、未解決の文書化判断だけを確認対象にする契約も固定する（issue #354）。

根拠: `tests/commands/test-workflow-contracts.sh:26-31`

`tests/commands/test-hazard-workflows.sh` は `/analyze-hazard-scan`・`/triage-issues-for-hazard`・`/work` の source 固有診断と label gate を静的検証し、旧 auto-approve 専用名称が戻らないことも確認する。

根拠: `tests/commands/test-hazard-workflows.sh:1-39`

`tests/install/test-install.sh` は isolated fixture HOME に installer を2回実行し、symlink、hook migration、Codex native status line 登録の統合契約と冪等性を検証する。`tests/install/test-setup-statusline-for-codex.sh` は fresh config、`[tui]` 不在、既存 status line 置換、他設定の維持、再実行を個別に検証する。

根拠: `tests/install/test-install.sh:1-176`, `tests/install/test-setup-statusline-for-codex.sh:1-122`

`tests/hooks/test-session-paths.sh` は `hooks/lib/session-paths.sh`（issue #316）の functional test である。`session-approved`/`session-tmp-dir` 両モードの既定 formula、`CLAUDE_CODE_KIT_STATE_HOME`/`CLAUDE_CODE_KIT_SESSION_DIR`/`CLAUDE_CODE_KIT_SESSION_APPROVED_FILE`/`CLAUDE_CODE_KIT_TMP_ROOT` オーバーライドの優先順位、symlink 経由実行時の自己位置解決、不正引数時の異常終了を検証する。

根拠: `tests/hooks/test-session-paths.sh:1-87`

`tests/commands/test-work-multi.sh` は `commands/work-multi.md` が `EnterWorktree` 呼び出しと `commands/work.md` への委譲のみで構成されゲート定義を重複していないこと、`ORIGINAL_WORKDIR` を lazy linker 初期化に限定して以後の操作を隔離 worktree に留めること、`skills/work-multi/SKILL.md` の scope guard、`commands/work.md` の worktree パスガードと `worktree-` prefix ベースのブランチ分類、lazy linker と shared status helper の契約を静的検証する。`tests/scripts/test-worktree-status.sh` は manifest 記録済み symlink を除外し、実際の変更と単体 `/work` 相当の通常 status を保持することを functional に検証する。

根拠: `tests/commands/test-work-multi.sh:1-83`

`tests/commands/test-task-manager.sh` はinput boundary、real task-worker、complete Draft setのapproved-head context、input-order `/git-pr-merge` delegation、embedded delivery mechanicsのabsence、partial completion、A/M/D/R documentation handling、completion commentを検証する。`tests/commands/test-git-pr-merge.sh` はstandalone/delegated approval、head drift、known/unknown commit、latest-main refresh、CI/local fallback、actual-branch conflict repair、Draft/Ready、local main prohibition、explicit squash verificationを検証する。

根拠: `tests/commands/test-task-manager.sh:1-139`, `tests/commands/test-git-pr-merge.sh:1-81`

`tests/scripts/test-link-worktree-untracked.sh` は lazy linker の functional test である。`prepare` が source と空 manifest だけを記録し、`link` が指定された untracked/ignored path だけを作成・manifest へ一度だけ記録することを確認する。tracked path、unsafe path、unavailable path は拒否する。

根拠: `tests/scripts/test-link-worktree-untracked.sh:1-208`

`tests/scripts/test-rename-thread.sh` は Claude transcript への custom title 追記、session ID 不在時の no-op、空 title の拒否を検証する。`tests/scripts/test-worktree-status.sh` は manifest 記録済み symlink を除外しつつ、実際の untracked/modified path と通常 worktree の status を保持する。

根拠: `tests/scripts/test-rename-thread.sh:1-48`, `tests/scripts/test-worktree-status.sh:1-95`

## Install and Status Line

`install.sh` は commands、hooks、scripts、skills、templates、global instructions を Claude/Codex の target へ symlink し、`scripts/setup_statusline_for_codex.sh` を実行する。その後 `jq` があれば hook migration と idempotent registration を行う。Codex status line は jq gate より前に設定される。

`scripts/setup_statusline_for_claude.sh` は `scripts/statusline.sh` を `~/.claude/statusline.sh` に symlink し、settings に `statusLine` を追加する。`scripts/setup_statusline_for_codex.sh` は既存 TOML の他設定を維持しながら `[tui].status_line` を `context-used`, `used-tokens`, `five-hour-limit`, `weekly-limit` へ冪等更新する。Codex は取得不能な項目を表示時に省略する。

根拠: `install.sh:12-211`, `scripts/setup_statusline_for_claude.sh:6-57`, `scripts/setup_statusline_for_codex.sh:6-93`, `scripts/statusline.sh:10-83`

`scripts/analyze_access.py` / `analyze_auto_approve.py` / `analyze_token_usage.py` は `logs/<type>/*.log` を月単位（`--month YYYY-MM` / `--all` / 省略時は最新月）でパースし、集計結果を JSON として標準出力へ出力する（対応する `/analyze-*` command から呼ばれる）。`scripts/lib/analyze_common.py` が対象月解決・ログ列挙・CLI引数定義・百分位計算（`percentile()`）を3スクリプト共通で提供する。`analyze_token_usage.py` は `logs/token-usage/*.log` がセッションごとの累積値である点を踏まえ、セッションIDごとの最終行のみを集計する。3スクリプトとも、対応する hook 自身の実行時間（`duration_ms`）を `duration_ms_stats` として集計する。

根拠: `scripts/analyze_access.py:1-6`, `scripts/analyze_auto_approve.py:1-6`, `scripts/analyze_token_usage.py:1-9`, `scripts/lib/analyze_common.py:1`

`scripts/link-worktree-untracked.sh` は `commands/work-multi.md` から呼ばれる lazy linker である。`prepare <source>` は source worktree と空 manifest を session tmp directory に記録する。`link <relative-path>` は `.git`・`.claude`・absolute path・parent traversal を拒否し、source 側が `??`/`!!` として報告する path だけを current worktree に link する。同じ source target は冪等に扱い、成功した path は manifest に一度だけ記録する。`scripts/worktree-status.sh` はこの manifest を使い、`??`/`!!` の完全一致または親 directory の entry だけを除外して残りの porcelain status を返す。manifest が空または不在なら通常の status を返す。

根拠: `scripts/link-worktree-untracked.sh:1-59`

## VitePress Site and CI

`site/package.json` は `docs:dev`, `docs:build`, `docs:preview` を定義する。dependencies は `@fortawesome/fontawesome-free`、devDependencies は `vitepress`。lock file では `@fortawesome/fontawesome-free` 6.7.2 と `vitepress` 1.6.4 が解決される。

`site/.vitepress/config.mts` は VitePress の `locales` オプションで多言語対応（i18n）を定義する。`root`（英語 / en-US）、`ja`（日本語 / ja-JP）、`zh`（中国語簡体字 / zh-CN）の 3 ロケールを持ち、各ロケールに nav・sidebar・footer を個別に定義する。コンテンツは `site/`（英語）、`site/ja/`（日本語）、`site/zh/`（中国語）に配置される。日本語版の concept・policy・specification ページは `docs/L0_concept/` および `docs/L3_implementation/specification_summary.md` を `@include` で参照する。

`.github/workflows/deploy.yml` は main push と `workflow_dispatch` を trigger とし、Node.js 24 で `site/` に対して `npm ci` と `npm run docs:build` を実行し、`site/.vitepress/dist` を GitHub Pages に deploy する。

根拠: `site/package.json:1-14`, `site/package-lock.json:765-766`, `site/package-lock.json:2486-2487`, `site/.vitepress/config.mts:1-183`, `.github/workflows/deploy.yml:1-53`

## 未確認事項

現時点で仕様サマリに混在させた未確認事項はない。
