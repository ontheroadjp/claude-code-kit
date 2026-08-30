# `commands/task.md`

## 目的・役割

docs 変更を伴う issue-specific implementation workflow。通常の単一 issue と `/task-manager` 配下の delegated worker が同一の調査・plan・実装・validation・documentation・Ready PR contract を共有する。

根拠: `commands/task.md:1-44`

## 動作の概要

- 通常モードは `/work` から単一作業として呼ばれ、ユーザー gate を直接扱う。
- delegated worker mode は `/work` の complete project context と isolated worktree/branch を受け取り、issue-specific な不足だけを shortest-path で補完する。
- いずれも plan approval 後に実装・tests・L3 per-file docs・`/docs-sync`・`/git-pr` を順に実行し、Ready PR を作る。
- delegated mode は Ready PR handoff を `/task-manager` へ返し、merge、parent cleanup、stash restoration を行わない。
- delegated batch の先頭 worker は、Ready PR の final remote head と validated latest-main base が一致した状態で approved full suite を成功させた場合だけ、SHA-bound validation evidence を handoff に含める。後続 worker と ordinary mode は evidence を生成しない。

根拠: `commands/task.md:26-44`, `commands/task.md:67-229`

## 主要な判定ロジック

- handed-off evidence の再読は `missing evidence`、`stale evidence`、`base drift` の path/range/reason を記録した場合だけ許可する。
- plan approval 前に file edit を行わず、session-approved へ tool/file/L3 scope を一度だけ書く。
- delegated worker は `/task-manager` 経由で issue-specific plan/implementation approval を受け、同じ worker が Ready PR まで継続する。
- 通常モードだけ branch を作り、delegated mode は payload の branch/worktree を再利用する。
- delegated mode は `task.md`・`coding-*.md`・`work-run-events.sh` を payload の絶対パス（`Command root`・`Work-run events helper`）から読み、ファイルシステム探索をしない。helper が `unavailable` なら event emit を省略する。
- reusable evidence は `validated_head_sha`、`validated_base_sha`、exact `full` scope、exact validation plan、`success` outcome をすべて持つ場合だけ生成する。head/base drift、失敗、targeted-only result は evidence に昇格しない。

根拠: `commands/task.md:35-50`, `commands/task.md:76-156`, `commands/task.md:227-245`

## 重要な設計判断

- ordinary/delegated task の実装契約を一つにし、task-manager が function/test/doc plan を再定義する二重構造をなくす。
- project-wide context は `/work`、issue-specific judgment は `/task`、parallel state/delivery order は `/task-manager` に分離する。
- PR は ordinary path と同じ Ready 状態まで作り、worker 固有の Draft-only result を導入しない。
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
- merge order 2件目以降は先行 delivery で base が変わるため、PR preparation では targeted validation に留め、authoritative full validation を delivery 時に行う。

## 変更履歴（git log より自動生成）

- 5c22e8b feat(#408): carry resolved command and helper paths in worker payload
- 3a2f223 feat(#406): forbid batching approval gates across task-manager issues (#407)
- 29b88f2 feat(#404): reuse SHA-bound full-suite validation (#405)
- 9fc5b9a feat(#401): add structured work run observability (#403)
- 72a11b5 feat(#400): unify work entry point (#402)
- a9fbb5f fix(#369): generate conventional task PR titles (#395)
- 4f0953a docs(task): remove /rename step from Step 3 pre-implementation checklist
- 5f1d984 #377 Add independent task-manager batch workflow (#378)
- 0bc7683 #344 Add a thread-renaming helper (#346)
- f32ec17 #336 Rename thread on work branch switch (#337)

## Work-run observability

work-run contextがある場合、plan/implementation/Ready PRのissue-specific stateとapproval waitだけをbest-effort emitする。ordinary modeは親session context、delegated modeはworker attach済みcontextを使い、logging failureで実装を停止しない。

根拠: `commands/task.md`（Work-run event contract）
