# `commands/task.md`

## 目的・役割

docs 変更を伴う issue-specific implementation workflow。通常の単一 issue と `/task-manager` 配下の delegated worker が同一の調査・plan・実装・validation・documentation・Ready PR contract を共有する。

根拠: `commands/task.md:1-44`

## 動作の概要

- 通常モードは `/work` から単一作業として呼ばれ、ユーザー gate を直接扱う。
- delegated worker mode は `/work` の complete project context と `Base SHA`（起動時点の latest `origin/main`）を受け取り、issue-specific な不足だけを shortest-path で補完する。作業ブランチは事前作成されず、plan 承認後に worker 自身が共有 working tree の現在 HEAD（= `Base SHA`）から `feat/<issue-number>-<slug>` を作る。別 worktree は作らない。
- いずれも plan approval 後に実装・tests・L3 per-file docs・`/docs-sync`・`/git-pr` を順に実行し、Ready PR を作る。
- delegated mode は Ready PR handoff を `/task-manager` へ返し、merge、parent cleanup、stash restoration を行わない。
- delegated mode の全 worker は、Ready PR の final remote head 確定後に approved full suite を issue につき1回実行し、成功時のみ SHA-bound validation evidence を handoff に含める。base は payload の `Base SHA`（latest `origin/main`。handoff 直前に依然 latest であることを確認する）。ordinary mode は evidence を生成しない。

根拠: `commands/task.md:43-57`, `commands/task.md:71-246`

## 主要な判定ロジック

- handed-off evidence の再読は `missing evidence`、`stale evidence`、`base drift` の path/range/reason を記録した場合だけ許可する。
- plan approval 前に file edit を行わず、session-approved へ tool/file/L3 scope を一度だけ書く。
- delegated worker は `/task-manager` 経由で issue-specific plan/implementation approval を受け、同じ worker が Ready PR まで継続する。
- 通常モードも delegated mode も、plan 承認後に worker が作業ブランチを作る。通常モードは approved plan の slug、delegated mode は payload の `Base SHA`（共有 working tree の現在 HEAD、latest `origin/main`）を根にする。別 worktree は作らず、branch の付け替えもしない。
- delegated mode は `task.md`・`coding-*.md`・`work-run-events.sh` を payload の絶対パス（`Command root`・`Work-run events helper`）から読み、ファイルシステム探索をしない。helper が `unavailable` なら event emit を省略する。
- reusable evidence は `validated_head_sha`、`validated_base_sha`（latest `origin/main`）、exact `full` scope、exact validation plan、`success` outcome をすべて持つ場合だけ生成する。head/base drift、失敗、targeted-only result は evidence に昇格しない。

根拠: `commands/task.md:43-57`, `commands/task.md:132-159`, `commands/task.md:232-245`

## 重要な設計判断

- ordinary/delegated task の実装契約を一つにし、task-manager が function/test/doc plan を再定義する二重構造をなくす。
- project-wide context は `/work`、issue-specific judgment は `/task`、直列実装順/delivery order は `/task-manager` に分離する。
- PR は ordinary path と同じ Ready 状態まで作り、worker 固有の Draft-only result を導入しない。
- delegated worker は `#(k-1)` が squash 済みの latest `origin/main` から分岐して実装する（#412 の approved-head chain を撤回、issue #414）。base が本物の latest `origin/main` なので、full-suite を issue につき1回だけ結合状態に対して回せば足り、`/git-pr-merge` は #404 の厳密な head/base/plan SHA 一致でのみ evidence を再利用する。
- full-suite evidence は final Ready PR head の確定後にだけ生成し、pre-commit validation や後から docs commit が加わる途中 head を再利用可能として扱わない。

## 統合ポイント

- caller: `commands/work.md`、`commands/task-manager.md`
- docs: `commands/docs-sync.md`
- publication: `commands/git-pr.md`
- commit: `commands/git-commit.md`
- session scope: installed `hooks/lib/session-paths.sh`

## 注意事項・既知の制限

- delegated mode でも plan・実装レビュー・Ready PR の approval は issue ごとに必須で、`/task-manager` は他 worker の gate と束ねずに relay する。
- worker は merge、parent workspace cleanup、stash restoration を行わない。
- L3 per-file docs 以外の aggregate docs は `/docs-sync` が diff を事実として更新する。
- batch は入力順に1 issue ずつ完全直列で処理され、`#(k+1)` の worker は `#k` の delivery 完了後に起動する。実装 wall time は直列（3 issue で概ね 3×）。
- 全 delegated worker が PR preparation で結合状態に対する authoritative full-suite を1回実行し、`/git-pr-merge` は #404 の厳密な head/base/plan SHA 一致でのみその evidence を再利用する。

## 変更履歴（git log より自動生成）

- a405d08 feat(#412): chain delegated workers on the predecessor's approved PR head
- abe4573 feat(#410): consolidate the shared work-run event contract into work.md (#411)
- ff0872c feat(#408): carry resolved command and helper paths in worker payload (#409)
- 3a2f223 feat(#406): forbid batching approval gates across task-manager issues (#407)
- 29b88f2 feat(#404): reuse SHA-bound full-suite validation (#405)
- 9fc5b9a feat(#401): add structured work run observability (#403)
- 72a11b5 feat(#400): unify work entry point (#402)
- a9fbb5f fix(#369): generate conventional task PR titles (#395)
- 4f0953a docs(task): remove /rename step from Step 3 pre-implementation checklist
- 5f1d984 #377 Add independent task-manager batch workflow (#378)

## Work-run observability

共有契約は `commands/work.md`「Work-run observability › 共有契約」を参照し再記述しない。`/task` は plan/implementation/Ready PR の issue-specific state と approval wait だけを emit する。ordinary modeは親session context、delegated modeはworker attach済みcontext（helper パスは payload の `Work-run events helper`）を使う。

根拠: `commands/task.md`（Work-run event contract）
