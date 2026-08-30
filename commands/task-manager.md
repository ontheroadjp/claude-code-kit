# /task-manager

`/work` から2〜3件の accepted implementation issue を受け取り、delegated `/task` worker の調査・plan を並行、実装を入力順に直列（chain）で管理し、承認済み PR を入力順に delivery する internal batch orchestrator です。standalone implementation entry point ではありません。

## 呼び出し契約

呼び出し元 `/work` から次を必ず受け取る。

```text
accepted_issues: <input order, complete issue metadata and readiness result>
project_context: <complete Phase 1 structured project-wide evidence>
base_sha: <validated base>
workspace_owner: /work
stash_state: <owned by /work>
work_run_id: <logical /work run id, if logging start succeeded>
```

- input validation、issue readiness、project-wide investigation を再実行しない。
- handed-off evidence を routine reread しない。
- parent workspace の checkout、stash、cleanup を行わない。
- payload が欠ける場合は mutation せず `/work` へ failure を返す。

## 責務と不変条件

- membership、実装順（chain）、delivery order は `/work` が渡した入力順で固定する。
- issue ごとに `investigating`、`awaiting_plan_approval`、`implementing`、`awaiting_pr_approval`、`delivery_eligible`、`delivering`、`completed`、`failed` を独立管理する。
- approval wait、repair、failure は unrelated worker の調査・plan 作成を止めない。実装フェーズは chain 順で、`#k`（入力順 k≥2）は `#(k-1)` の PR 承認後に開始する。
- accepted issue ごとに real `task-worker` sub-agent を1つ起動し、model override を指定しない。`MAX_TASK_WORKERS = 3`。
- worker は同じ worktree/branch 上で delegated `commands/task.md` を完全に Read し、同 workflow の delegated worker mode を実行する。
- source/test/docs の調査・plan・実装・validation・PR 作成契約を親で複製しない。
- delivery は入力順に `/git-pr-merge` へ委譲する。
- parent workspace と stash の cleanup owner は常に `/work`。

## Phase 1: worker lifecycle

issue ごとに、latest `origin/main` の validated base から branch と isolated worktree を1つずつ作る（1 issue = 1 worker = 1 worktree）。investigation と planning は全 worker が並行で行い、実装以降だけを入力順に直列化する（chain）。

```text
branch:   feat/<issue-number>-<short-slug>
worktree: <repo-root>/.claude/worktrees/task-manager-<batch-id>-<issue-number>
```

- 全 worker の branch は validated base から作る。branch の付け替え（`reset` 等の rewriting 操作）はしない。
- `#1` は plan 承認後すぐ実装へ進む。
- `#k`（入力順 k≥2）は plan 承認後も実装を開始せず、`#(k-1)` の PR gate 承認を待つ。承認されたら worker は自分の branch へ `#(k-1)` の approved PR head SHA を normal non-rewriting merge（`git merge <predecessor approved head>` 相当）で取り込み、承認済み plan を merge 後の状態と突き合わせてから実装へ進む（差分の扱いは Phase 2 plan gate 節）。
- `#(k-1)` の delivery（squash merge）完了は待たない。approved PR head は承認後に変わらないため、その SHA だけを取り込む。

worker payload:

```text
Role: delegated task-worker
Repository root: <absolute path>
Worktree: <absolute isolated worktree path>
Branch: <issue branch>
Issue: <complete accepted issue metadata>
Base SHA: <validated base SHA — 全 worker 共通、branch の根>
Merge order: <position>/<batch size>
Predecessor approved head: <#(k-1) の approved PR head SHA。position 1 では none。position k≥2 では #(k-1) の PR gate 承認時に確定して worker へ渡す>
Predecessor PR: <#(k-1) の PR number。position 1 では none>
Project-wide context: <complete /work handoff>
Work run ID: <work_run_id or unavailable>
Command root: <absolute installed commands dir for the executing agent: ~/.claude/commands or ~/.codex/commands>
Work-run events helper: <absolute installed work-run-events.sh path for the executing agent: ~/.claude/scripts/work-run-events.sh or ~/.codex/scripts/work-run-events.sh, or unavailable>
L3 doc root: <Worktree>/docs/L3_implementation

Required:
1. Read <Command root>/task.md completely. Its coding-*.md siblings are in the same directory.
2. Execute delegated worker mode without re-running /work gates.
3. Return the issue-specific plan before editing.
4. For position k≥2: after the plan is approved, wait for the predecessor PR approval, then merge `Predecessor approved head` into the branch and reconcile the approved plan before editing.
5. Continue as the same worker after approval.
6. Create one Ready PR and return its implementation handoff without merging it.

Forbidden:
- routine reread of handed-off evidence
- edit before issue-specific plan approval
- starting implementation for position k≥2 before the predecessor PR is approved and its approved head is merged into the branch
- invoking /work or duplicating /task
- filesystem-searching for task.md, coding-*.md, or work-run-events.sh instead of using the payload paths
- Draft-only delivery, merging or delivering its own PR, force push, history rewrite, destructive cleanup
```

worker は logging が利用可能な場合、編集前に payload の `Work-run events helper` literal パスで `attach` を best-effort 実行する。パスの探索はしない。`Work-run events helper` が `unavailable` の場合は attach を省略する。`worker_registered` の共通 `agent_session_id` が既存 access / approval / token log との join key になる。

```text
bash <Work-run events helper> attach <work_run_id> issue_number=<N> worker_id=<stable-worker-id> branch=<branch> worktree=<absolute-worktree> || true
```

work-run event の共有契約は `commands/work.md` の「Work-run observability › 共有契約（work-run events を emit する全 command 共通）」に従う。`/task-manager` と各 worker は、それぞれが所有する遷移だけを emit する:

- `worker_registered`（上記 `attach` による worker 起動時）
- `issue_state_changed issue_number=<N> state=<state>`（所有する issue state 遷移時）
- `approval_wait_started` / `approval_wait_finished`（plan gate・PR gate。詳細は各 gate 節）
- `approved_head_recorded`（PR 承認時。詳細は PR gate 節）

replacement worker には worktree/branch、project context、supplemental findings、approved plan、current state、failure evidence をすべて渡し、承認済み調査をやり直さない。`#k`（k≥2）の replacement には `Predecessor approved head` と、それが branch へ merge 済みかどうかも渡す。

## Phase 2: independent approval relay

worker message を到着順に処理する。

### 非バッチ制約（必須）

approval relay は issue ごとに完全独立で行う。次を禁止する。

- ready な plan / 実装レビュー / PR handoff を、他 issue の handoff と足並みを揃える目的で保留すること。到着した時点で、他 issue の状態に関係なくその issue 単独で提示する。
- 複数 issue の plan・実装レビュー・PR gate を1つのプロンプトに束ねて提示すること。gate は常に「issue #N の ○○ をレビューしてください」という単一 issue の問いにする。
- 複数 issue をまとめて承認・却下させること。承認・却下・修正指示は1 issue ずつ受け、対象 issue だけに適用する。
- 「両方揃ってから」「まとめて最終承認」「整合性をまとめて確認」を判断根拠にすること。chain 実装により `#k` は既に `#(k-1)` を内包するため、独立 PR 間の latest-main 取り込みや挙動差を「まとめて確認」する必要はない。

gate の提示・承認は常に対象 issue の handoff 到着だけで進み、他 issue の gate と足並みを揃えない。cross-issue の待ちは次の2つだけに限られ、いずれも gate をまとめる理由にはしない: (1) `#k`（k≥2）の実装フェーズ開始は `#(k-1)` の PR gate 承認を前提とする（chain 実装順）、(2) Phase 3 の fixed-order delivery。それ以外の investigating・plan・実装レビュー・PR の各 gate は、対象 issue の handoff 到着だけで進む。

worker message の待機中は、状態遷移のない進捗ナレーション（「まだ両 worker が作業中です」等）を新しいターンとして出力しない。単一の長い wait を発行し、実 worker message の到着または必須の user gate 到来時にだけ発話する。

### plan gate

delegated `/task` が返した issue-specific plan を到着後すぐユーザーへ提示する。plan は全 worker が並行で作るため複数 issue の plan が相前後して到着しうるが、提示・承認は常に1 issue ずつ行う。修正・拒否・approval reset は対象 issue だけに適用する。

- `#1`: plan 承認で即 `implementing` に進め、同じ worker に approval を返す。
- `#k`（k≥2）: plan 承認後は `implementing` に進めず、`#(k-1)` の PR gate 承認を待つ。`#(k-1)` が承認されたら、その approved head SHA を worker payload の `Predecessor approved head` として渡し、worker に「`#(k-1)` approved head を branch へ merge → 承認済み plan と merge 後の状態を突き合わせ」を指示してから `implementing` に進める。突き合わせで承認済み plan の前提が実質変わらなければ worker はそのまま実装する。approved plan の範囲・対象・検証方法が material に変わる場合は、worker が差分を添えて plan gate へ再提示し、対象 issue だけを再承認する。

待機開始・回答確定時は `approval_wait_started issue_number=<N> approval_kind=plan` と `approval_wait_finished issue_number=<N> approval_kind=plan outcome=<approved|rejected>` を best-effort emit する。

### PR gate

worker が Ready PR handoff を返したら、remote head、diff scope、documentation completeness、validation を確認してすぐ個別提示する。`#k`（k≥2）の Ready PR は `#(k-1)` が delivery されるまで diff に `#(k-1)` の変更を含む（chain 実装で内包しているため）。レビューは `#k` の増分に注目し、diff scope の説明でこの点を明示する。

worker が `full_validation_evidence` を返した場合は、field の完全性と Ready PR remote head との一致だけを確認して保持する。task-manager 自身は reuse 可否を判断せず、evidence の補完・推測・生成も行わない。evidence がない PR も通常どおり approval と delivery の対象にする。

> issue #N の Ready PR をレビューしてください。これでよいですか？

- NG: 対象 worker だけを再開し、同じ PR を修正・再提示する。
- OK: full `approved_head_sha`、approved scope/behavior、final validation plan を記録して `delivery_eligible` にする。加えて、後続 `#(N+1)` が実装待ちなら、この `approved_head_sha` を `Predecessor approved head` として `#(N+1)` worker へ渡し実装を解禁する（plan gate 節参照）。

PR gate も同様に `approval_kind=pr` の wait events を emit し、承認時は `approved_head_recorded issue_number=<N> pr_number=<PR> head_sha=<full-sha>` を emit する。

他 issue の plan・実装レビュー・PR approval 待ちは unrelated worker の investigation・planning を止めない。`#k` の実装フェーズだけは設計上 `#(k-1)` の PR 承認を待つ。

## Phase 3: fixed-order delivery

`commands/git-pr-merge.md` を完全に Read する。入力順の先行 issue がすべて `completed` で、対象 issue が `delivery_eligible` の場合だけ delivery する。後続 issue は eligibility を保持して待機する。

chain 実装により `#k`（k≥2）の Ready PR は既に `#(k-1)` の approved 変更を内包している。したがって delivery 時の `/git-pr-merge` の latest-main refresh は tree 変化のない trivial merge になり、sibling-worker divergence 由来の conflict は構造的に発生しない（`main_refresh_result` の期待値は `outcome=success conflict_count=0`。非0 は想定外の外部変更で、standalone PR と同じ扱い）。parallel 実装時代の delivery-time conflict 解決経路は到達不能になる。

```text
pr_number: <approved PR number>
approved_head_sha: <approved full head SHA>
approved_scope_or_behavior: <source, test, documentation, observable behavior>
final_validation_plan: <required CI and local fallback>
approval_source: task-manager issue-specific Ready PR approval
owned_worktree: <task-worker worktree or isolated repair worktree permission>
known_delivery_changes: <trivial latest-main merge and mechanical documentation refresh>
predecessor_approved_head: <#(k-1) の approved PR head SHA。position 1 では none>
full_validation_evidence: <SHA-bound successful full-suite evidence returned by that issue's task worker（chain では全 worker が返す）>
```

`/git-pr-merge` が actual PR branch で latest main refresh、current documentation truth、reused-or-executed authoritative current-head validation、squash merge、GitHub merged state を確認した後だけ `completed` とする。validation evidence の再利用判定は `/git-pr-merge` だけが所有する。chain delivery では evidence の base が `predecessor_approved_head` であり、`/git-pr-merge` はこれを trivial refresh merge をまたいで authoritative として再利用するため、delivery 時に full-suite を再実行しない（詳細は `commands/git-pr-merge.md`）。

mechanical latest-main/citation/history/catalog/aggregate-doc refresh と approved behavior を変えない repair は再承認不要。source behavior/public contract、design/security boundary、approved scope、unknown remote diff が変わる場合は対象 PR だけ `awaiting_pr_approval` に戻す。

## Phase 4: return to /work

全 issue 完了時または途中停止時に、次を `/work` へ返す。

```text
issue_states:
approved_and_current_heads:
ready_pr_urls:
delivery_results:
validation_results:
forwarded_full_validation_evidence:
remaining_worktrees:
manual_recovery:
```

issue completion comment は投稿できるが、failure は merge failure にしない。clean で owned な issue worktree は cleanup candidate として返し、parent workspace、stash、force cleanup を操作しない。完了済み merge は rollback しない。

## 運用制約

- user は通常 `/work #x #y` を使う。`/task-manager` の直接起動時は `/work` からの required handoff がないため、`/work` の利用を案内して終了する。
- 1 batch は2〜3 issue。queue、自動 issue 選定、cross-session resume、distributed lock、batch state 永続化を持たない。
- final batch documentation PR を作らない。各 delegated `/task` の Ready PR が required docs を含む。
