# `/task-manager`

## 目的・役割

ユーザーから入力された1〜3件のimplementation issueを入力順に実行するbatch executorである。issue readinessとplan gateを親agentが管理し、source preparationはissueごとのreal `task-worker`へ、review済みsource PRのdeliveryは `/git-pr-merge` へ委譲する。全source delivery後にlocalized documentation PRを1本作成・mergeする。

根拠: `commands/task-manager.md:1-31`

## 動作の概要

1. issue token、repository、GitHub auth、open state、labels、blockers、management sub-issues、existing workをread-only検証する。
2. 親agentがissue-specific planを作り、全planへのcombined approvalを得る。
3. issueごとのisolated worktreeとbranchを作成し、最大3つのreal `task-worker`を並行起動する。
4. workerはsource/testの実装、validation、commit、push、Draft PR、structured handoffまでを担当する。
5. complete Draft PR setを一括提示し、PRごとのhead SHA、scope/behavior、final validation planを承認状態として固定する。
6. input orderで各PRを `/git-pr-merge` へdelegated context付きで渡し、merged stateとsquash SHA反映後だけ次へ進む。
7. merged changed-file unionをA/M/D/R分類し、latest mainをtruthとしてdocumentationを同期・mergeする。
8. source/documentation resultを各issueへcommentし、batch resultとmanual follow-upを報告する。

根拠: `commands/task-manager.md:54-145`, `commands/task-manager.md:147-273`, `commands/task-manager.md:275-394`

## 主要な判定ロジック

### issue readinessとexecutor boundary

入力は `^#[1-9][0-9]*$` の1〜3件に限定する。closed、agenda、未審査hazard、open blocker、未完了sub-issueを持つmanagement issue、既存PR/branch/worktreeがあるissueを含むbatchは開始しない。issue selection、batch compatibility、conflict-risk、merge-order optimizationは行わない。

根拠: `commands/task-manager.md:58-91`, `commands/task-manager.md:396-412`

### plan gateとtask-worker

repository mutation前に全issue planの明示承認を得る。worker数はaccepted issue数と一致し最大3、model overrideなしで親modelを継承する。worker payloadはapproved paths、worktree、branch、base、plan、禁止事項をself-containedに渡し、documentation、Ready化、mergeを禁止する。

根拠: `commands/task-manager.md:93-145`, `commands/task-manager.md:147-245`

### Draft set approvalとdelivery delegation

complete Draft setだけを提示し、PR番号、full head SHA、approved scope/behavior、final validation planを固定する。Phase 4は `commands/git-pr-merge.md`を完全に読み、同contextとowned worktreeを各PRへ入力順に渡す。latest-main merge、conflict repair、CI/local validation、Ready transition、squash mergeのstate machineはtask-managerへ複製しない。

unknown commitまたはmaterial delivery changeはcomplete set全体ではなく対象PRだけを再レビューする。途中停止時は完了済みmergeをauthoritativeとしてcompleted/pending stateを報告し、rollback-capableなbatch transactionを仮定しない。

根拠: `commands/task-manager.md:247-296`

### status-aware documentation finalization

scopeはmerged source PR changed-file union、truthはfinalization時のlatest main、PR diffはfresh docs branchとlatest mainの差分である。AddedはL3作成、Modifiedは更新、Deletedは削除または明示retire、RenamedはL3移動とcitation再生成を行い、aggregate docs、README、test index、config、schema、public surfaceも評価する。

source delivery後にdocsが完了しなければsourceをrollbackせず、`source complete / documentation incomplete`と報告してstandalone `/init-docs` recoveryを案内する。

根拠: `commands/task-manager.md:298-359`

### completion comments

全merge確認後、各issueへsource PR URLとapproved/delivered/squash SHA、documentation PR URL/SHA、validation、documentation scopeをcommentする。comment failureはmerge failureではなくmanual follow-upとする。

根拠: `commands/task-manager.md:361-383`

## 重要な設計判断

- task-managerはbatch planningとsource preparationを担うが、単一PR delivery transactionは再利用可能な `/git-pr-merge`へ一元化する。
- batch approvalはreviewed head SHAを固定し、外部pushをPR単位で再承認させる。
- merged PRをrollbackせず、部分完了をcompleted/pending stateとしてmanual recovery可能にする。
- documentationをsource PRから分離し、A/M/D/R statusを失わず1回だけ同期する。
- issue選定やmerge順最適化を行わず、user-provided orderのexecutorに限定する。

## 統合ポイント

- Codex wrapper: `skills/task-manager/SKILL.md`
- source delivery: `commands/git-pr-merge.md`
- worker protocol: command内のinternal `task-worker`
- contract test: `tests/commands/test-task-manager.sh`
- documentation truth: repository profile、primary docs、latest main

## 注意事項・既知の制限

- batch state、cross-session resume、distributed lock、background monitorを持たない。
- 同一repositoryでは同時に1つのtask-manager sessionという運用disciplineに依存する。
- process停止後のworktree、branch、Draft PR、partial mergeはmanual recovery対象である。
- completion comment failureは別途手動投稿が必要である。

## 変更履歴（git log より自動生成）

- 57dce6c feat(#389): add reviewed PR delivery workflow
- 6dc29d5 #387 Simplify task-manager source delivery (#388)
- b2b83ac #384 Replace task-manager pre-integration with sequential PR refresh (#385)
- 823f676 #381 Align task-manager source PR titles with work (#382)
- 8a9903f #379 Reuse task-manager integration conflict resolutions (#380)
- 5f1d984 #377 Add independent task-manager batch workflow (#378)
