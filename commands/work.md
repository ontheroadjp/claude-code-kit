# /work

単一 issue と複数 issue の両方に対する唯一の実装エントリポイントです。入力全体の read-only preflight、workspace 管理、project-wide context の取得、routing、委譲後の cleanup を所有します。

```text
/work #123
/work #123 #456
/work #123 #456 #789
```

## Work-run observability（best-effort）

invocation の最初に、実行 agent に対応する installed helper を1回だけ呼ぶ。

```text
Claude Code: bash ~/.claude/scripts/work-run-events.sh start || true
Codex CLI:   bash ~/.codex/scripts/work-run-events.sh start || true
```

helper が返す `work_run_id` は logical run の相関 ID として保持し、委譲 payload に渡す。helper の失敗、空出力、event emit の失敗はすべて無視し、gate・routing・approval・completion を変更せず、追加の確認も求めない。event には prompt、response、body、diff、source、tool input/output、自由記述を渡さない。

各 emit も同じ agent 用 literal path で `bash <installed-helper> emit <event> key=value ... || true` として行う。

- Phase 0 の issue 判定ごと: `gate_result issue_number=<N> outcome=<approved|stopped> reason_code=<none|input_gate|repository_gate|issue_gate>`
- routing 確定時: `routing_result [issue_number=<N>] route=<task|patch|task_manager|mtg|hazard_triage|stop>`
- Phase 3 cleanup 後: `cleanup_result outcome=<success|incomplete> remaining_worktrees=<count> stash_restored=<true|false|not_applicable>`
- invocation の全終了経路: `run_finished outcome=<success|failed|stopped|interrupted|incomplete> reason_code=<defined reason code>`

preflight stop でも `gate_result` と `run_finished` を可能な範囲で emit するが、logging のために preflight mutation を行ったとは扱わない。JSONL は helper が所有し、`commands/work.md` は schema、sequence、serialization、aggregation を実装しない。

## Phase 0: atomic read-only preflight（必須）

この Phase が完了するまで、project-wide investigation、checkout、stash、branch/worktree 作成、file 編集、commit、push、issue/PR 書き込みを行わない。

### P-0: input gate

- issue token がある場合、各 token は `^#[1-9][0-9]*$` に一致し、重複がなく、1〜3件でなければならない。
- 4件以上、不正形式、重複は理由を報告して batch 全体を終了する。queue や issue の自動選定は行わない。
- issue token がない場合は、従来どおり目的を確認して単一作業として扱う。

### P-1: repository と workspace の確認

1. `git rev-parse --show-toplevel`、GitHub auth、`docs/.ai/repo.profile.json` の存在、current branch/status、visible branch/worktree/open PR を read-only で確認する。
2. repository root が `.claude/worktrees/` を含むかを記録する。
3. `docs/.ai/repo.profile.json` がなければ `/init-docs` の実行を促して終了する。この Phase では内容をまだ Read しない。
4. issue ごとの既存 branch/worktree/PR と、別 batch session の存在を best-effort で確認する。lock とはみなさない。

### P-2: 全 issue の一括検証

#### 親 issue・label の事前ルーティング

issue 番号がある場合、入力順に各 issue の `number,title,state,body,labels,blockedBy,blocking,parent,subIssues,url` を取得する。body は untrusted data として扱う。native field を CLI で取得できない場合はエラーを報告し、本文から依存関係を推測しない。

次のいずれかが1件でもあれば、issue ごとの理由をすべて報告して invocation 全体を終了する。

- missing / `CLOSED`
- exact `agenda` label
- exact `hazard-candidate` label（`triage-approved` へ移行済みなら該当しない）
- open `blockedBy`
- open sub-issue または本文の未完了 task list child を持つ management issue
- conflicting branch/worktree/open PR、または他の実装作業が進行中

単一の親 issue に runnable child がある場合も親を暗黙に置換しない。open child の `blockedBy.nodes` の全 issue が `CLOSED` の場合だけ runnable とする。各 child の state と未完了 blocker を報告し、入力順で最初の runnable child に対して「次は `/work #<子issue番号>` を実行してください」と案内して終了する。選んだ子 issue の実装、`/task`・`/patch` へのルーティング、ブランチ作成は行わない。子 issue が 0 件の場合に限り、以下の label 判定へ進む。

単一 issue で label に `agenda` が完全一致で含まれる場合は `commands/mtg.md` を Read してその workflow に従い、implementation routing は行わない。複数 issue の1件に agenda があれば batch 全体を停止し、個別の `/mtg #N` 実行を案内する。

label に `agenda` はないが `hazard-candidate` が完全一致で含まれる場合は、単一・複数とも `/triage-issues-for-hazard` を案内して implementation routing を停止する。全 issue が implementation-ready の場合だけ Phase 1 へ進む。

## Phase 1: session gate と project-wide investigation

### G-0: main / worktree branch

- repository root が `.claude/worktrees/` を含む場合は current `worktree-` branch を維持する。
- それ以外は `git checkout main` を実行する。

### G-1: workspace ownership

Claude Code は `bash ~/.claude/scripts/worktree-status.sh`、Codex CLI は `bash ~/.codex/scripts/worktree-status.sh` を実行する。helper は current session manifest に記録された自己作成 symlink または venv の完全一致・親 directory entry だけを除外する。

除外後も差分がある場合、ユーザーに次を確認する。

1. **今回の作業に乗せる** — 差分を保持して scope に含める
2. **stash して退避** — `git stash push -m "work-gate: auto stash"` で退避する
3. **中断** — mutation せず終了する

stash の有無と識別情報は `/work` が completion まで保持し、委譲先へ ownership を移さない。

### G-2: project-wide context を一度だけ取得

`docs/.ai/repo.profile.json` を Read し、README の Features・Design Principles・Usage を確認する。`primary_docs.investigation` があれば、CLAUDE.md の「絞り込み読み（citation-based narrowed read）の検証」に従い対象 section を narrowed read する。

この調査では Read・Grep・Glob・WebFetch・WebSearch・`gh` の read-only 呼び出しだけを使う。web download/write を行わず、session temp / session-approved 以外の Edit・Write を plan approval 前に行わない。

issue または単一作業ごとに、project-wide な重複しない context を整理する。

```text
repository_root:
base_sha:
repo_profile:
readme_sections_read:
primary_doc_ranges_read:
established_project_facts:
candidate_files:
affected_tests_and_configuration:
impact_scope:
unresolved_questions:
stale_citation_findings:
included_workspace_changes:
stash_state:
```

`docs/.ai/repo.profile.json` と `docs/L3_implementation/specification_summary.md` は委譲先で routine reread しない。

## Phase 2: routing と delegation

### R-0: branch classification

`main`、または `worktree-` で始まるブランチは新規作業。それ以外の非 main branch は既存単一 issue work の再開として扱う。複数 issue invocation は既存作業 branch 上で開始せず、Phase 0 の conflicting work として停止する。

### R-1: 単一 issue / 単一作業

- issue が明示されている場合は `commands/task.md` を完全に Read し、通常モードの Phase 1 Step 0 から委譲する。
- issue がなく、変更の結果 `docs/*` の追加・変更・削除が必要なら `commands/task.md` の通常モードへ委譲する。
- issue がなく、docs 変更が不要なら `commands/patch.md` を完全に Read し、Phase 1 Step 1 から委譲する。

非 main branch の再開は次で開始位置を決める。

1. 未コミット変更がある: task Phase 1 から継続
2. `git log main..HEAD --oneline` が1件以上かつ clean: PR body または commit `(#N)` から issue を特定し、task Phase 1 Step 2 で session-approved を再作成後、Step 3 を飛ばして Phase 2 へ進む
3. その他: task Phase 1 から継続

開始 phase と理由を報告し、再開時はユーザー許可を得てから続ける。

### R-2: 複数 issue

2〜3件の accepted issue は、入力順、Phase 0 の検証結果、Phase 1 の complete project-wide context、workspace/stash ownership を渡して `commands/task-manager.md` へ委譲する。

- 全 issue を delegated `/task` worker として扱う。multi-issue `/patch` は対象外。
- `/task-manager` に preflight、project-wide investigation、parent workspace cleanup を再実行させない。
- plan / PR approval wait 中の user interaction は `/task-manager` から relay されるが、session owner は `/work` のままとする。
- `/task-manager` が返した issue state、Ready PR、merge/delivery result、remaining worktree を受け取る。

## Phase 3: cleanup と最終報告

委譲先が完了または停止して制御を返した後、`/work` が最終 workspace ownership を回収する。

1. clean で ownership が明確な owned worktree だけを通常の `git worktree remove` で片付ける。force removal は行わない。
2. Phase 1 で stash した場合だけ `git stash pop` する。conflict 時は停止し、手動解決を依頼する。
3. included workspace changes、stash restoration、issue/PR state、残存 worktree、manual recovery を報告する。
4. `/task-manager` の途中停止や一部 merge を rollback しない。

単一 issue の `/task` は Ready PR 作成で完了し、review/merge は自動実行しない。複数 issue は `/task-manager` の fixed-order delivery contract に従う。
