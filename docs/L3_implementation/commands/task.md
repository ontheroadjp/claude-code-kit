# `commands/task.md`

## 目的・役割

docs 変更を伴う issue-specific implementation workflow。通常の単一 issue と `/task-manager` 配下の delegated worker が同一の調査・plan・実装・validation・documentation・Ready PR contract を共有する。

根拠: `commands/task.md:1-44`

## 動作の概要

- 通常モードは `/work` から単一作業として呼ばれ、ユーザー gate を直接扱う。
- delegated worker mode は `/work` の complete project context と isolated worktree/branch を受け取り、issue-specific な不足だけを shortest-path で補完する。
- いずれも plan approval 後に実装・tests・L3 per-file docs・`/docs-sync`・`/git-pr` を順に実行し、Ready PR を作る。
- delegated mode は Ready PR handoff を `/task-manager` へ返し、merge、parent cleanup、stash restoration を行わない。

根拠: `commands/task.md:26-44`, `commands/task.md:67-229`

## 主要な判定ロジック

- handed-off evidence の再読は `missing evidence`、`stale evidence`、`base drift` の path/range/reason を記録した場合だけ許可する。
- plan approval 前に file edit を行わず、session-approved へ tool/file/L3 scope を一度だけ書く。
- delegated worker は `/task-manager` 経由で issue-specific plan/implementation approval を受け、同じ worker が Ready PR まで継続する。
- 通常モードだけ branch を作り、delegated mode は payload の branch/worktree を再利用する。

根拠: `commands/task.md:35-43`, `commands/task.md:76-156`

## 重要な設計判断

- ordinary/delegated task の実装契約を一つにし、task-manager が function/test/doc plan を再定義する二重構造をなくす。
- project-wide context は `/work`、issue-specific judgment は `/task`、parallel state/delivery order は `/task-manager` に分離する。
- PR は ordinary path と同じ Ready 状態まで作り、worker 固有の Draft-only result を導入しない。

## 統合ポイント

- caller: `commands/work.md`、`commands/task-manager.md`
- docs: `commands/docs-sync.md`
- publication: `commands/git-pr.md`
- commit: `commands/git-commit.md`
- session scope: installed `hooks/lib/session-paths.sh`

## 注意事項・既知の制限

- delegated mode でも plan と Ready PR の approval は issue ごとに必須。
- worker は merge、parent workspace cleanup、stash restoration を行わない。
- L3 per-file docs 以外の aggregate docs は `/docs-sync` が diff を事実として更新する。

## 変更履歴（git log より自動生成）

- f52dd59 feat(#400): unify work entry point
- a4cc791 fix(#369): generate conventional task PR titles
- 0331e9e feat(#336): rename thread on work branch switch
- 1aa3c2d fix(#318): distinguish worktree-untracked symlinks from real changes via manifest
