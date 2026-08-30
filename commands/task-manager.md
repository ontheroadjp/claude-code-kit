# /task-manager

`/work` から2〜3件の accepted implementation issue を受け取り、delegated `/task` worker を入力順に**完全直列で1件ずつ**実装・delivery する internal batch orchestrator です。standalone implementation entry point ではありません。

## 呼び出し契約

呼び出し元 `/work` から次を必ず受け取る。

```text
accepted_issues: <input order, complete issue metadata and readiness result>
project_context: <complete Phase 1 structured project-wide evidence>
base_sha: <validated base — 各 worker は起動時点の latest origin/main から branch を作る>
workspace_owner: /work
stash_state: <owned by /work>
work_run_id: <logical /work run id, if logging start succeeded>
```

- input validation、issue readiness、project-wide investigation を再実行しない。
- handed-off evidence を routine reread しない。
- parent workspace の checkout、stash、cleanup を行わない。
- payload が欠ける場合は mutation せず `/work` へ failure を返す。

## 責務と不変条件

- membership、実装順、delivery order は `/work` が渡した入力順で固定する。
- issue ごとに `investigating`、`awaiting_plan_approval`、`implementing`、`awaiting_pr_approval`、`delivery_eligible`、`delivering`、`completed`、`failed` を管理するが、**同時に active な worker は常に1つ**であり、`#(k+1)` の worker は `#k` が `origin/main` に squash merge されて `completed` になってから起動する。
- accepted issue ごとに real `task-worker` sub-agent を1つ、入力順に起動する。model override を指定しない。`MAX_TASK_WORKERS = 1`（同時実行数。1 batch の issue 数は2〜3）。
- worker は共有 working tree 上で delegated `commands/task.md` を完全に Read し、同 workflow の delegated worker mode を実行する。
- **per-issue worktree を作らない。** 同時に実装する issue が1件だけなので、delegated worker は ordinary `/task` と同じく共有 working tree 上で作業ブランチを切り替えて実装する。branch の付け替え（`reset` 等の rewriting 操作）はしない。
- source/test/docs の調査・plan・実装・validation・PR 作成契約を親で複製しない。
- delivery は入力順に `/git-pr-merge` へ委譲する。`/git-pr-merge` は delivery 用の isolated worktree を自分で作成する。
- parent workspace と stash の cleanup owner は常に `/work`。

## Phase 1: serial worker lifecycle

accepted issue を入力順に**1件ずつ**処理する。`#k` の全ステップ（起動 → plan gate → 実装 → PR gate → delivery → `completed`）が終わるまで `#(k+1)` を起動しない。

各 issue `#k` について:

1. 共有 working tree を `main` に置き、`git fetch origin` 後に latest `origin/main` へ fast-forward する（`#(k-1)` の squash commit を含む状態）。この SHA を `Base SHA` として payload に載せる。
2. real `task-worker` sub-agent を1つ起動し、下記 payload を渡して `<Command root>/task.md` の delegated worker mode を実行させる。
3. plan gate と PR gate を Phase 2 に従って issue 単独で relay する。
4. PR 承認後、Phase 3 に従って `/git-pr-merge` へ delivery を委譲する。
5. `completed` を確認したら次の issue へ進む。

```text
branch: feat/<issue-number>-<short-slug>（worker が plan 承認後に共有 working tree 上で作成する。task-manager は事前作成しない）
```

worker payload:

```text
Role: delegated task-worker
Repository root: <absolute path>
Branch: <事前作成しない。worker が plan 承認後、共有 working tree の現在 HEAD（= Base SHA）から feat/<issue-number>-<slug> を作る>
Issue: <complete accepted issue metadata>
Base SHA: <full latest origin/main SHA at this worker's launch — worker の branch の根であり、up-front full suite の base>
Input position: <k>/<batch size>
Project-wide context: <complete /work handoff>
Work run ID: <work_run_id or unavailable>
Command root: <absolute installed commands dir for the executing agent: ~/.claude/commands or ~/.codex/commands>
Work-run events helper: <absolute installed work-run-events.sh path for the executing agent: ~/.claude/scripts/work-run-events.sh or ~/.codex/scripts/work-run-events.sh, or unavailable>
L3 doc root: <Repository root>/docs/L3_implementation

Required:
1. Read <Command root>/task.md completely. Its coding-*.md siblings are in the same directory.
2. Execute delegated worker mode without re-running /work gates.
3. Return the issue-specific plan before editing.
4. After the plan is approved, create the work branch from the current shared working tree HEAD (latest origin/main = Base SHA), then implement.
5. Continue as the same worker after approval.
6. Create one Ready PR and return its implementation handoff without merging it.

Forbidden:
- routine reread of handed-off evidence
- edit before issue-specific plan approval
- invoking /work or duplicating /task
- filesystem-searching for task.md, coding-*.md, or work-run-events.sh instead of using the payload paths
- creating a separate worktree — implementation happens in the shared working tree, one issue at a time
- Draft-only delivery, merging or delivering its own PR, force push, history rewrite, destructive cleanup
```

worker は logging が利用可能な場合、作業ブランチ作成後・編集前に payload の `Work-run events helper` literal パスで `attach` を best-effort 実行する。パスの探索はしない。`Work-run events helper` が `unavailable` の場合は attach を省略する。`worker_registered` の共通 `agent_session_id` が既存 access / approval / token log との join key になる。

```text
bash <Work-run events helper> attach <work_run_id> issue_number=<N> worker_id=<stable-worker-id> branch=<branch> worktree=<Repository root> || true
```

work-run event の共有契約は `commands/work.md` の「Work-run observability › 共有契約（work-run events を emit する全 command 共通）」に従う。`/task-manager` と各 worker は、それぞれが所有する遷移だけを emit する:

- `worker_registered`（上記 `attach` による worker 起動時）
- `issue_state_changed issue_number=<N> state=<state>`（所有する issue state 遷移時）
- `approval_wait_started` / `approval_wait_finished`（plan gate・PR gate。詳細は各 gate 節）
- `approved_head_recorded`（PR 承認時。詳細は PR gate 節）

replacement worker には branch、project context、supplemental findings、approved plan、current state、failure evidence をすべて渡し、承認済み調査をやり直さない。

## Phase 2: independent approval relay

worker message を到着順に処理する。batch は1 issue ずつ直列に進むため、複数 issue の handoff が同時に ready になることはない。

### 非バッチ制約（必須）

approval relay は issue ごとに完全独立で行う。次を禁止する。

- ready な plan / 実装レビュー / PR handoff を、他 issue の handoff と足並みを揃える目的で保留すること。到着した時点で、他 issue の状態に関係なくその issue 単独で提示する。
- 複数 issue の plan・実装レビュー・PR gate を1つのプロンプトに束ねて提示すること。gate は常に「issue #N の ○○ をレビューしてください」という単一 issue の問いにする。
- 複数 issue をまとめて承認・却下させること。承認・却下・修正指示は1 issue ずつ受け、対象 issue だけに適用する。
- 「両方揃ってから」「まとめて最終承認」「整合性をまとめて確認」を判断根拠にすること。batch は常に1 issue in flight で、`#k` は `#(k-1)` が squash 済みの main から分岐しているため、独立 PR 間の整合を「まとめて確認」する必要はない。

gate の提示・承認は常に対象 issue の handoff 到着だけで進む。cross-issue の待ちは1つだけ: `#(k+1)` の worker 起動は `#k` の delivery 完了（`completed`）を前提とする。それ以外の investigating・plan・実装レビュー・PR の各 gate は、対象 issue の handoff 到着だけで進む。

worker message の待機中は、状態遷移のない進捗ナレーション（「まだ worker が作業中です」等）を新しいターンとして出力しない。単一の長い wait を発行し、実 worker message の到着または必須の user gate 到来時にだけ発話する。

### plan gate

delegated `/task` が返した issue-specific plan を到着後すぐユーザーへ提示する。提示・承認は常に1 issue ずつ行い、修正・拒否・approval reset は対象 issue だけに適用する。

- plan 承認で即 `implementing` に進め、同じ worker に approval を返す。worker は承認済み plan の base（`Base SHA` = latest `origin/main`）から作業ブランチを作成して実装する。

待機開始・回答確定時は `approval_wait_started issue_number=<N> approval_kind=plan` と `approval_wait_finished issue_number=<N> approval_kind=plan outcome=<approved|rejected>` を best-effort emit する。

### PR gate

worker が Ready PR handoff を返したら、remote head、diff scope、documentation completeness、validation を確認してすぐ個別提示する。`#k` の Ready PR の diff は `#k` の変更だけを含む（`#(k-1)` は既に `origin/main` にある）。

worker が `full_validation_evidence` を返した場合は、field の完全性と Ready PR remote head との一致だけを確認して保持する。task-manager 自身は reuse 可否を判断せず、evidence の補完・推測・生成も行わない。evidence がない PR も通常どおり approval と delivery の対象にする。

> issue #N の Ready PR をレビューしてください。これでよいですか？

- NG: 対象 worker だけを再開し、同じ PR を修正・再提示する。
- OK: full `approved_head_sha`、approved scope/behavior、final validation plan を記録して `delivery_eligible` にする。

PR gate も同様に `approval_kind=pr` の wait events を emit し、承認時は `approved_head_recorded issue_number=<N> pr_number=<PR> head_sha=<full-sha>` を emit する。

## Phase 3: fixed-order delivery

`commands/git-pr-merge.md` を完全に Read する。入力順の先行 issue がすべて `completed` で、対象 issue が `delivery_eligible` の場合だけ delivery する（batch は1 issue ずつ進むため、in-flight の PR は常に1本）。

`#k` は `#(k-1)` が squash merge 済みの latest `origin/main` から分岐している。したがって delivery 時の `/git-pr-merge` の latest-main refresh は通常 no-op か clean fast-forward であり、conflict は起動後に外部変更が入った場合にのみ、standalone PR と同じ扱いで発生する。

```text
pr_number: <approved PR number>
approved_head_sha: <approved full head SHA>
approved_scope_or_behavior: <source, test, documentation, observable behavior>
final_validation_plan: <required CI and local fallback>
approval_source: task-manager issue-specific Ready PR approval
owned_worktree: <permission to create an isolated delivery worktree for this PR>
known_delivery_changes: <trivial latest-main merge and mechanical documentation refresh>
full_validation_evidence: <SHA-bound successful full-suite evidence returned by that issue's task worker>
```

`/git-pr-merge` が actual PR branch で latest main refresh、current documentation truth、reused-or-executed authoritative current-head validation、squash merge、GitHub merged state を確認した後だけ `completed` とする。validation evidence の再利用判定は `/git-pr-merge` だけが所有する（#404 の厳密な head/base/plan SHA 一致）。

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

issue completion comment は投稿できるが、failure は merge failure にしない。`/git-pr-merge` が作成した delivery worktree が残っていれば cleanup candidate として返し、parent workspace、stash、force cleanup を操作しない。完了済み merge は rollback しない。

## 運用制約

- user は通常 `/work #x #y` を使う。`/task-manager` の直接起動時は `/work` からの required handoff がないため、`/work` の利用を案内して終了する。
- 1 batch は2〜3 issue。同時に active な worker は1つ。queue、自動 issue 選定、cross-session resume、distributed lock、batch state 永続化を持たない。
- final batch documentation PR を作らない。各 delegated `/task` の Ready PR が required docs を含む。
