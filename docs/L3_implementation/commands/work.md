# `commands/work.md`

## 目的・役割

単一 issue と2〜3件の複数 issue の唯一の実装入口であり、atomic preflight、workspace/stash ownership、project-wide context、routing、最終 cleanup を一元管理する。

根拠: `commands/work.md:1-11`

## 動作の概要

1. Phase 0 は入力形式、repository/auth/profile、workspace、全 issue の state・label・dependency・既存作業を read-only で検証する。1件でも不正なら mutation 前に invocation 全体を止める。
2. parent issue は runnable child を報告して終了し、単一 agenda は `/mtg`、hazard candidate は hazard triage へ案内する。
3. Phase 1 は main/worktree branch と dirty workspace を扱い、profile・README・primary investigation doc から project context を一度だけ作る。
4. 単一 work は通常 `/task` または `/patch`、2〜3件は complete handoff とともに internal `/task-manager` へ委譲する。
5. 委譲終了後は `/work` が owned worktree cleanup と、自ら作成した stash の復元を行う。

根拠: `commands/work.md:13-153`

## 主要な判定ロジック

- issue token は `^#[1-9][0-9]*$`、重複なし、最大3件。
- agenda、hazard-candidate、open blocker、management child、conflicting work は atomic failure。native dependency が取得できない場合は推測しない。
- `main` と `worktree-` branch は新規作業、それ以外は単一 issue の再開。複数 issue は既存 work branch 上で開始しない。
- multi-issue `/patch` は扱わず、accepted issue はすべて delegated `/task` worker へ進む。

根拠: `commands/work.md:17-50`, `commands/work.md:98-135`

## 重要な設計判断

- 全 issue の validation を project investigation と mutation より前に置き、batch の部分着手を防ぐ。
- project-wide evidence は session owner が一度だけ取得し、delegated worker は具体的な missing/stale/base-drift 理由なしに再読しない。
- cleanup と stash restoration を `/work` に残し、worker failure や partial delivery 時も ownership を一意にする。
- single agenda routing、parent-child selection、worktree prefix classification は既存の安全境界を維持する。

## 統合ポイント

- 単一 implementation: `commands/task.md`
- docs 不要の単一 patch: `commands/patch.md`
- 複数 issue orchestration: `commands/task-manager.md`
- agenda: `commands/mtg.md`
- workspace filter: installed `scripts/worktree-status.sh`

## 注意事項・既知の制限

- 1 invocation は最大3 issue。queue、自動 issue 選定、multi-issue patch は持たない。
- preflight は best-effort な existing-work detection であり distributed lock ではない。
- 完了済み merge は cleanup failure 時にも rollback しない。

## 変更履歴（git log より自動生成）

- 3aff0cc feat(#410): consolidate the shared work-run event contract into work.md
- 9fc5b9a feat(#401): add structured work run observability (#403)
- 72a11b5 feat(#400): unify work entry point (#402)
- bf1692f feat(#363): add narrowed-read verification principle and track offset/limit usage (#364)
- cf6fcba #360 Align /work heading wording and (A)/(B) investigation references (#361)
- e501904 #358 Prohibit web write/download during /work investigation phase (#359)
- 4ddff6e #356 Prohibit edits during /work investigation phase (#357)
- f484a2d Route parent issues to their next ready child (#351)
- 446c4d3 #343 Replace report review with human-led mtg agendas (#345)
- ea565ac #326 Automate worktree symlink status filtering (#327)

## Work-run observability

§Work-run observability は2部構成。`### 共有契約（work-run events を emit する全 command 共通）` が best-effort・no-content・context がある時だけ emit・helper パスは受け取った literal・schema は helper 所有・自分の遷移だけ emit の6不変条件を一度だけ定義し、`/task`・`/task-manager`・`/patch`・`/git-pr`・`/git-pr-merge`・`/docs-sync` はこの見出しを参照するだけで再記述しない。`### /work が emit する event` が `/work` 固有分（start 呼び出し・`work_run_id` handoff・gate_result・routing_result・cleanup_result・run_finished）を定義する。event 名と key の正準は `scripts/work-run-events.sh` の `allowed_event()` / `allowed_key()`。

根拠: `commands/work.md`（Work-run observability › 共有契約 / /work が emit する event）, `scripts/work-run-events.sh`
