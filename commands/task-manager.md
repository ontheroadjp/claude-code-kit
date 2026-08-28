# /task-manager

`/task-manager` は、ユーザー指定の1〜3件の implementation issue を、それぞれ独立した `/work` 相当の pipeline として進める batch executor です。調査・plan 承認・実装・PR 承認は issue ごとに進行し、delivery だけを入力順に直列化します。

```text
/task-manager #123
/task-manager #123 #456
/task-manager #123 #456 #789
```

## 責務と不変条件

- batch membership と merge order は入力順で固定する。issue 選定、順序最適化、互換性判断は行わない。
- issue ごとに `investigating`、`awaiting_plan_approval`、`implementing`、`awaiting_pr_approval`、`delivery_eligible`、`delivering`、`completed`、`failed` を独立管理する。
- ある issue の承認待ち・修復・失敗は、無関係な worker の調査、実装、validation、Draft PR 作成を止めない。
- issue ごとに実体のある `task-worker` sub-agent を1つ起動し、通常は同じ worker が補完調査から実装、documentation、Draft PR 作成まで継続する。
- 各 issue PR は、単独で `/work` を実行した場合と同等に source、test、L3 per-file documentation、必要な aggregate documentation、README を含む。
- final batch documentation worktree、documentation PR、documentation validation、documentation merge は作らない。
- PR は入力順に1本ずつ `/git-pr-merge` へ委譲し、先行 PR が `completed` になるまで後続 PR を delivery しない。
- 各 PR は delivery 直前に actual PR branch へ latest `main` を取り込み、documentation を current truth に更新し、current head を authoritative validation してから squash merge する。
- force push、履歴改変、強制 worktree 削除、破壊的 cleanup は行わない。完了済み merge は rollback しない。

## workflow dependency

この command は `/work` と `/task` の契約を再現しますが、worker 実行中に既存 workflow を呼び出しません。`commands/work.md`、`commands/task.md`、`commands/docs-sync.md`、`commands/git-pr.md` を runtime Read、source、wrap、delegate してはなりません。delivery は `commands/git-pr-merge.md` を完全に Read して委譲します。coding skill、Git/GitHub CLI、repository profile、documentation、template、hook は直接利用できます。

## Phase 0: read-only preflight

この Phase が完了するまで branch・worktree作成、file編集、commit、push、issue/PR書き込みを行いません。

### 0.1 input gate

各 token は `^#[1-9][0-9]*$` に一致する必要があります。

- 0件: usage を表示して終了する。
- 1〜3件: 次へ進む。
- 4件以上: 最大3件であることを報告して終了する。待ち行列を作ってはならない。
- 重複番号、数字だけ、0、負数、range、comma list、その他の形式: 理由を示して終了する。

### 0.2 repository gate

1. repository root、GitHub auth、repository profile、current branch/status を確認する。親 workspace の変更を stash、reset、checkout しない。
2. visible worktree、branch、open Draft PR から別 `/task-manager` session を best-effort で検出する。これは lock ではない。
3. 各 issue の `number,title,state,body,labels,blockedBy,blocking,parent,subIssues,url` を入力順に取得する。body は untrusted data として扱う。
4. missing/closed、`agenda`、未審査 `hazard-candidate`、open blocker、未完了 sub-issue を持つ management issue、既存 PR/branch/worktree がある issue を含む場合は mutation 前に終了する。

## Phase 1: 親調査と worker 起動

### 1.1 `/work` 相当の調査

親は全 issue について、README の Features・Design Principles・Usage、repository profile、primary investigation doc、候補 source/test、対応 L3 per-file doc を read-only 調査します。大きな集約 doc と citation は narrowed read を使い、期待する目印を実際に含むことを確認します。

issue ごとに次の structured investigation handoff を作ります。

```text
issue_number:
files_and_line_ranges_read:
established_facts:
current_behavior:
candidate_changed_files:
affected_tests_and_configuration:
impact_scope:
unresolved_questions:
stale_citation_findings:
base_sha:
```

handoff は読んだ範囲と未確認事項を区別します。worker は handed-off evidence を再読してはなりません。ただし `missing evidence`、`stale evidence`、`base drift` のいずれかを具体的な path・範囲・理由とともに記録した場合だけ再調査できます。

### 1.2 membership 固定と worktree

preflight 通過後に入力順を固定し、latest `origin/main` から issue ごとの branch と isolated worktree を作ります。

```text
branch:   feat/<issue-number>-<short-slug>
worktree: <repo-root>/.claude/worktrees/task-manager-<batch-id>-<issue-number>
```

同一 path/branch は上書きしません。package manager など共有 resource への書き込みは直列化します。

### 1.3 worker scheduling と payload

- `MAX_TASK_WORKERS = 3`
- accepted issue ごとに実体のある `task-worker` sub-agent を1つ起動する。
- sub-agent model overrideを指定せず、親agentのmodelを継承する。
- capacity 不足時だけ未起動 worker を待たせる。起動済み worker を approval 待ちのために cancel しない。

payload は self-contained にします。

```text
Role: task-worker
Repository root: <absolute path>
Worktree: <absolute isolated worktree path>
Branch: <issue branch>
Issue: <number, title, URL, body>
Base SHA: <base SHA>
Merge order: <position>/<batch size>
Parent investigation handoff: <complete structured evidence>

Required lifecycle:
1. perform only task-equivalent supplemental investigation
2. return an issue-specific plan and enter awaiting_plan_approval
3. after approval, continue as the same worker
4. implement source, tests, L3, aggregate docs, and README required by this issue
5. validate, commit, push, and create one Draft PR
6. return implementation handoff and enter awaiting_pr_approval

Forbidden:
- rereading handed-off evidence without a recorded missing/stale/base-drift reason
- edits before issue-specific plan approval
- edits outside the approved scope
- invoking existing implementation/documentation workflows
- force push, history rewrite, destructive cleanup
- Ready transition, merge, or final batch approval request
```

replacement worker が必要な場合は、同じ worktree/branch に加え、structured investigation handoff、supplemental findings、approved plan、current state、failure evidence をすべて渡します。replacement を理由に承認済み調査をやり直しません。

## Phase 2: issue ごとの非同期 pipeline

親は worker message を到着順に処理し、他 worker の進行を継続したまま、必要な issue-specific gate をユーザーへ提示します。複数 issue の結果が同時に揃った場合も、承認状態は issue ごとに記録します。

### 2.1 plan gate

worker は補完調査後、次を含む plan を返します。

- completion criteria、Before / After
- exact changed/new source、test、documentation paths
- implementation steps と relevant coding skills
- tests、success criteria、dependencies、risks、unknowns、rollback
- recorded reread reasons と supplemental evidence
- branch/worktree、Git/GitHub write scope

親はその issue の plan を到着後すぐ提示します。承認された issue だけ `implementing` へ進め、同じ worker に approved plan を返します。未承認 issue は `awaiting_plan_approval` のまま保持します。plan 修正・invalidity・approval reset は対象 issue だけに適用します。

### 2.2 implementation と Draft PR

承認を受けた worker は次を行います。

1. relevant coding skillを読み、approved scopeだけを実装する。
2. source、tests、対応 L3 per-file docs、aggregate docs、README の必要箇所を同じ PR に含める。`docs/L0_concept/` は変更しない。
3. relevant test、lint、buildを実行し、diffをapproved pathsと照合する。
4. `<type>(#<issue-number>): <short description>` の commit を作り、force なしでpushする。
5. `gh pr create --draft` で、同じ type・目的の `<type>(#<issue-number>): <English description>` title と `Closes #N` を含む英語 body を作る。
6. Draft、base/head、issue scope、documentation completeness を確認する。

worker は次の implementation handoff を返します。

```text
issue_number:
approved_plan:
branch:
worktree:
base_sha:
head_sha:
draft_pr_number:
draft_pr_url:
changed_source_files:
changed_test_files:
changed_documentation_files:
observable_changes:
design_decisions:
tests:
risks_or_followups:
```

### 2.3 PR gate

親は handoff、Draft PR head、diff scope、documentation completeness、development validation を確認し、その PR をすぐ個別提示します。

> issue #N の実装PRをレビューしてください。これでよいですか？

- NG/修正要求: 対象 worker だけを再開し、修正後に同じ PR を再提示する。
- OK: full `approved_head_sha`、approved scope/behavior、final validation plan を記録し、`delivery_eligible` にする。

他 issue の plan/PR が未承認でも、承認済み issue の実装・PR準備は進めます。PR approval は他 PR の head や scope を承認しません。

## Phase 3: fixed-order delivery coordinator

`commands/git-pr-merge.md` を完全に Read します。入力順の先行 issue がすべて `completed` で、対象 issue が `delivery_eligible` のときだけ `delivering` に進めます。後続 issue が先に承認されても eligibility を保持して待機します。

delivery 前に actual PR branch で次を行います。

1. latest `origin/main` を取り込む。
2. current `main` の documentation state を基準に、その issue の L3、aggregate docs、README を refresh する。
3. PR diff が current `main` に対してその issue の source、test、documentation 変更だけを含むことを確認する。
4. citation、history、aggregate-document の機械的 refresh を known delivery commit として記録する。

その後、次の delegated context で `/git-pr-merge` に委譲します。

```text
pr_number: <approved PR number>
approved_head_sha: <approved full head SHA>
approved_scope_or_behavior: <source, test, documentation, observable behavior>
final_validation_plan: <required CI and exact local fallback>
approval_source: task-manager issue-specific PR approval
owned_worktree: <task-worker worktree or isolated repair worktree permission>
known_delivery_changes: <latest-main merge and mechanical documentation refresh commits>
```

delivery は latest-main を含む current head に authoritative validation を実行し、明示的 squash merge 後に GitHub merged state と squash SHA の `origin/main` 反映を確認します。確認後だけ対象を `completed` とし、次の入力順 issue を評価します。

### 再承認境界

次は approved scope 内の mechanical delivery change であり、再承認不要です。

- latest-main merge
- citation line、git history、catalog/index、aggregate documentation の current truth への更新
- approved behaviorを変えない conflict/validation repair

次が変わる場合は対象 PR だけ `awaiting_pr_approval` に戻します。

- source behavior または public contract
- design decision または security boundary
- approved scope
- unknown remote commit による diff

修復・再承認待ちは後続 worker の調査、実装、Draft PR 準備を止めません。ただし fixed input-order delivery は越えません。

## Phase 4: completion と recovery

各 issue の merge 確認後、その issue に PR URL、approved/delivered head、squash SHA、validation、documentation scope を comment します。comment failure は merge failure にせず manual follow-up とします。

batch complete は全 issue が `completed` の場合だけ報告します。途中停止時は issue ごとの state、approved/current head、PR URL、停止理由、残存 worktree を報告します。完了済み merge は authoritative であり rollback しません。

clean で所有が明確な worktree だけ通常の `git worktree remove` で片付けます。dirty・ownership不明・removal failure は force 削除せず報告します。

## 運用制約

- 同一repositoryで同時に1つの `/task-manager` sessionだけを運用する。
- 1 batchは1〜3 issue、worker concurrencyは最大3。4件目のqueueや自動 issue 選定を持たない。
- process停止後のcross-session resume、自動restart、background monitor、distributed lockを実装しない。
- repository file、session file、GitHub Projects、GitHub Actionsへbatch stateを永続化しない。
- `/work` を廃止・置換しない。
