# `/task-manager`

## 目的・役割

ユーザー指定の1〜3件のimplementation issueを、issueごとに独立したwork-equivalent pipelineとして進めるbatch executorである。調査・plan承認・実装・PR承認は独立して進め、source deliveryだけを入力順に直列化する。

根拠: `commands/task-manager.md:1-21`

## 動作の概要

1. input、repository、GitHub auth、issue readiness、既存作業をmutation前に検証する。
2. 親が `/work` 相当の調査を行い、読んだ範囲、facts、候補file、影響、unknown、stale citationをstructured handoffにする。
3. issueごとのreal `task-worker`を起動し、workerは補完調査後すぐissue-specific planを返す。
4. 親はplanを到着順に提示し、承認されたissueだけ同じworkerで実装へ進める。
5. workerはsource、test、L3、aggregate docs、READMEを同じDraft PRに含め、PR単位の承認を待つ。
6. 承認済みPRはdelivery eligibleとなるが、`/git-pr-merge`への委譲は固定入力順で行う。
7. delivery直前にlatest mainとcurrent documentation truthを取り込み、issue-local diffとcurrent-head validationを確認してsquash mergeする。
8. issueごとにcompletion commentを投稿し、全issue完了時だけbatch completeを報告する。

根拠: `commands/task-manager.md:27-226`

## 主要な判定ロジック

### 独立state machine

各issueは `investigating`、`awaiting_plan_approval`、`implementing`、`awaiting_pr_approval`、`delivery_eligible`、`delivering`、`completed`、`failed` を持つ。approval wait、repair、failureは対象issueに局所化し、unrelated workerの調査・実装・PR準備を止めない。

根拠: `commands/task-manager.md:11-20`, `commands/task-manager.md:119-176`

### investigation handoff

親の調査結果はfile/line ranges、facts、current behavior、candidate files、tests/config、impact、unknown、stale citationを含む。workerの再読はmissing evidence、stale evidence、base driftを具体的に記録した場合だけ許可される。replacement workerにもevidence、補完調査、approved plan、current state、failure evidenceを渡す。

根拠: `commands/task-manager.md:47-68`, `commands/task-manager.md:88-117`

### work-equivalent PR

同じworkerがplan承認後にsource、tests、L3 per-file docs、aggregate docs、READMEを実装し、validation、commit、push、Draft PR作成まで担当する。sourceとdocumentationを別PRへ分けず、final batch documentation PRも作らない。

根拠: `commands/task-manager.md:136-165`

### fixed-order delivery

後続PRは先に承認されてもdelivery eligibilityを保持して待機し、先行issueがcompletedになったときだけdeliveryへ進む。actual PR branchへlatest mainとcurrent documentation truthを取り込み、current mainとの差分がそのissueだけに限定されることを確認して `/git-pr-merge`へ委譲する。

根拠: `commands/task-manager.md:178-201`

### 再承認境界

latest-main merge、citation/history/catalog/aggregate docsの機械的refresh、behaviorを変えないrepairは再承認しない。source behavior、public contract、design decision、security boundary、approved scope、unknown remote diffが変わる場合だけ対象PRを再承認状態へ戻す。

根拠: `commands/task-manager.md:203-218`

## 重要な設計判断

- approval barrierをbatch単位からissue単位へ変え、human wait中も独立作業を進める。
- investigation ownershipを親とworkerで分け、structured evidenceによって重複readを抑える。
- PRをwork-equivalentな自己完結単位とし、別documentation transactionを廃止する。
- parallel preparationとsequential deliveryを分離し、速度とdeterministic merge orderを両立する。
- mechanical refreshとmaterial changeを分け、不要な再承認を避けつつhuman controlを維持する。

## 統合ポイント

- Codex wrapper: `skills/task-manager/SKILL.md`
- delivery: `commands/git-pr-merge.md`
- internal worker: payloadで定義する `task-worker`
- contract test: `tests/commands/test-task-manager.sh`
- investigation truth: repository profile、primary docs、current implementation

## 注意事項・既知の制限

- batch stateはprocess memoryだけに保持し、cross-session resumeやdistributed lockを持たない。
- 同一repositoryでは同時に1つのtask-manager sessionという運用規律に依存する。
- worker concurrencyは最大3で、4件目のqueueやissue自動選定は行わない。
- process停止後のworktree、branch、Draft PR、partial mergeはmanual recovery対象である。

## 変更履歴（git log より自動生成）

- a4cc791 fix(#369): generate conventional task PR titles
- 57dce6c feat(#389): add reviewed PR delivery workflow
- 6dc29d5 #387 Simplify task-manager source delivery (#388)
- b2b83ac #384 Replace task-manager pre-integration with sequential PR refresh (#385)
- 823f676 #381 Align task-manager source PR titles with work (#382)
- 8a9903f #379 Reuse task-manager integration conflict resolutions (#380)
- 5f1d984 #377 Add independent task-manager batch workflow (#378)
