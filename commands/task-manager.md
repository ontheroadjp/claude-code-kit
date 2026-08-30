# /task-manager

`/work` から2〜3件の accepted implementation issue を受け取り、delegated `/task` worker を並行管理し、承認済み PR を入力順に delivery する internal batch orchestrator です。standalone implementation entry point ではありません。

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

- membership と delivery order は `/work` が渡した入力順で固定する。
- issue ごとに `investigating`、`awaiting_plan_approval`、`implementing`、`awaiting_pr_approval`、`delivery_eligible`、`delivering`、`completed`、`failed` を独立管理する。
- approval wait、repair、failure は unrelated worker の調査・実装・Ready PR 作成を止めない。
- accepted issue ごとに real `task-worker` sub-agent を1つ起動し、model override を指定しない。`MAX_TASK_WORKERS = 3`。
- worker は同じ worktree/branch 上で delegated `commands/task.md` を完全に Read し、同 workflow の delegated worker mode を実行する。
- source/test/docs の調査・plan・実装・validation・PR 作成契約を親で複製しない。
- delivery は入力順に `/git-pr-merge` へ委譲する。
- parent workspace と stash の cleanup owner は常に `/work`。

## Phase 1: worker lifecycle

latest `origin/main` の validated base から、issue ごとの branch と isolated worktree を作る。

```text
branch:   feat/<issue-number>-<short-slug>
worktree: <repo-root>/.claude/worktrees/task-manager-<batch-id>-<issue-number>
```

worker payload:

```text
Role: delegated task-worker
Repository root: <absolute path>
Worktree: <absolute isolated worktree path>
Branch: <issue branch>
Issue: <complete accepted issue metadata>
Base SHA: <base SHA>
Merge order: <position>/<batch size>
Project-wide context: <complete /work handoff>
Work run ID: <work_run_id or unavailable>
Command root: <absolute installed commands dir for the executing agent: ~/.claude/commands or ~/.codex/commands>
Work-run events helper: <absolute installed work-run-events.sh path for the executing agent: ~/.claude/scripts/work-run-events.sh or ~/.codex/scripts/work-run-events.sh, or unavailable>
L3 doc root: <Worktree>/docs/L3_implementation

Required:
1. Read <Command root>/task.md completely. Its coding-*.md siblings are in the same directory.
2. Execute delegated worker mode without re-running /work gates.
3. Return the issue-specific plan before editing.
4. Continue as the same worker after approval.
5. Create one Ready PR and return its implementation handoff without merging.

Forbidden:
- routine reread of handed-off evidence
- edit before issue-specific plan approval
- invoking /work or duplicating /task
- filesystem-searching for task.md, coding-*.md, or work-run-events.sh instead of using the payload paths
- Draft-only delivery, merge, force push, history rewrite, destructive cleanup
```

worker は logging が利用可能な場合、編集前に payload の `Work-run events helper` literal パスで `attach` を best-effort 実行する。パスの探索はしない。`Work-run events helper` が `unavailable` の場合は attach を省略する。`worker_registered` の共通 `agent_session_id` が既存 access / approval / token log との join key になる。

```text
bash <Work-run events helper> attach <work_run_id> issue_number=<N> worker_id=<stable-worker-id> branch=<branch> worktree=<absolute-worktree> || true
```

親と worker は、各 issue state 遷移時にそれぞれが所有する遷移だけを `emit issue_state_changed issue_number=<N> state=<state> || true` で記録する。重複した telemetry state machine は持たない。

replacement worker には worktree/branch、project context、supplemental findings、approved plan、current state、failure evidence をすべて渡し、承認済み調査をやり直さない。

## Phase 2: independent approval relay

worker message を到着順に処理する。

### 非バッチ制約（必須）

approval relay は issue ごとに完全独立で行う。次を禁止する。

- ready な plan / 実装レビュー / PR handoff を、他 issue の handoff と足並みを揃える目的で保留すること。到着した時点で、他 issue の状態に関係なくその issue 単独で提示する。
- 複数 issue の plan・実装レビュー・PR gate を1つのプロンプトに束ねて提示すること。gate は常に「issue #N の ○○ をレビューしてください」という単一 issue の問いにする。
- 複数 issue をまとめて承認・却下させること。承認・却下・修正指示は1 issue ずつ受け、対象 issue だけに適用する。
- 「両方揃ってから」「まとめて最終承認」「整合性をまとめて確認」を判断根拠にすること。独立 PR 間の latest-main 取り込みや挙動差の確認は Phase 3 delivery が担う。

cross-issue の順序待ちが許されるのは Phase 3 の fixed-order delivery だけである。それ以前の investigating・plan・implementing・実装レビュー・PR の各 gate は、対象 issue の handoff 到着だけで進み、他 issue を待たない。

worker message の待機中は、状態遷移のない進捗ナレーション（「まだ両 worker が作業中です」等）を新しいターンとして出力しない。単一の長い wait を発行し、実 worker message の到着または必須の user gate 到来時にだけ発話する。

### plan gate

delegated `/task` が返した issue-specific plan を到着後すぐユーザーへ提示する。承認された issue だけ `implementing` に進め、同じ worker に approval を返す。修正・拒否・approval reset は対象 issue だけに適用する。

待機開始・回答確定時は `approval_wait_started issue_number=<N> approval_kind=plan` と `approval_wait_finished issue_number=<N> approval_kind=plan outcome=<approved|rejected>` を best-effort emit する。

### PR gate

worker が Ready PR handoff を返したら、remote head、diff scope、documentation completeness、validation を確認してすぐ個別提示する。

worker が `full_validation_evidence` を返した場合は、field の完全性と Ready PR remote head との一致だけを確認して保持する。task-manager 自身は reuse 可否を判断せず、evidence の補完・推測・生成も行わない。evidence がない PR も通常どおり approval と delivery の対象にする。

> issue #N の Ready PR をレビューしてください。これでよいですか？

- NG: 対象 worker だけを再開し、同じ PR を修正・再提示する。
- OK: full `approved_head_sha`、approved scope/behavior、final validation plan を記録して `delivery_eligible` にする。

PR gate も同様に `approval_kind=pr` の wait events を emit し、承認時は `approved_head_recorded issue_number=<N> pr_number=<PR> head_sha=<full-sha>` を emit する。

他 issue の plan・実装レビュー・PR approval 待ちは unrelated worker を止めない。

## Phase 3: fixed-order delivery

`commands/git-pr-merge.md` を完全に Read する。入力順の先行 issue がすべて `completed` で、対象 issue が `delivery_eligible` の場合だけ delivery する。後続 issue は eligibility を保持して待機する。

```text
pr_number: <approved PR number>
approved_head_sha: <approved full head SHA>
approved_scope_or_behavior: <source, test, documentation, observable behavior>
final_validation_plan: <required CI and local fallback>
approval_source: task-manager issue-specific Ready PR approval
owned_worktree: <task-worker worktree or isolated repair worktree permission>
known_delivery_changes: <latest-main and mechanical documentation refresh>
full_validation_evidence: <optional SHA-bound successful full-suite evidence returned by the same task worker>
```

`/git-pr-merge` が actual PR branch で latest main refresh、current documentation truth、reused-or-executed authoritative current-head validation、squash merge、GitHub merged state を確認した後だけ `completed` とする。validation evidence の再利用判定は `/git-pr-merge` だけが所有する。

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
