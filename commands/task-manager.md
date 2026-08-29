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

Required:
1. Read commands/task.md completely.
2. Execute delegated worker mode without re-running /work gates.
3. Return the issue-specific plan before editing.
4. Continue as the same worker after approval.
5. Create one Ready PR and return its implementation handoff without merging.

Forbidden:
- routine reread of handed-off evidence
- edit before issue-specific plan approval
- invoking /work or duplicating /task
- Draft-only delivery, merge, force push, history rewrite, destructive cleanup
```

replacement worker には worktree/branch、project context、supplemental findings、approved plan、current state、failure evidence をすべて渡し、承認済み調査をやり直さない。

## Phase 2: independent approval relay

worker message を到着順に処理する。

### plan gate

delegated `/task` が返した issue-specific plan を到着後すぐユーザーへ提示する。承認された issue だけ `implementing` に進め、同じ worker に approval を返す。修正・拒否・approval reset は対象 issue だけに適用する。

### PR gate

worker が Ready PR handoff を返したら、remote head、diff scope、documentation completeness、validation を確認してすぐ個別提示する。

> issue #N の Ready PR をレビューしてください。これでよいですか？

- NG: 対象 worker だけを再開し、同じ PR を修正・再提示する。
- OK: full `approved_head_sha`、approved scope/behavior、final validation plan を記録して `delivery_eligible` にする。

他 issue の plan/PR approval 待ちは unrelated worker を止めない。

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
```

`/git-pr-merge` が actual PR branch で latest main refresh、current documentation truth、authoritative current-head validation、squash merge、GitHub merged state を確認した後だけ `completed` とする。

mechanical latest-main/citation/history/catalog/aggregate-doc refresh と approved behavior を変えない repair は再承認不要。source behavior/public contract、design/security boundary、approved scope、unknown remote diff が変わる場合は対象 PR だけ `awaiting_pr_approval` に戻す。

## Phase 4: return to /work

全 issue 完了時または途中停止時に、次を `/work` へ返す。

```text
issue_states:
approved_and_current_heads:
ready_pr_urls:
delivery_results:
validation_results:
remaining_worktrees:
manual_recovery:
```

issue completion comment は投稿できるが、failure は merge failure にしない。clean で owned な issue worktree は cleanup candidate として返し、parent workspace、stash、force cleanup を操作しない。完了済み merge は rollback しない。

## 運用制約

- user は通常 `/work #x #y` を使う。`/task-manager` の直接起動時は `/work` からの required handoff がないため、`/work` の利用を案内して終了する。
- 1 batch は2〜3 issue。queue、自動 issue 選定、cross-session resume、distributed lock、batch state 永続化を持たない。
- final batch documentation PR を作らない。各 delegated `/task` の Ready PR が required docs を含む。
