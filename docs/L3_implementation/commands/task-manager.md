# `/task-manager`

## 目的・役割

`commands/task-manager.md` は、1〜3件の implementation issue を1つのbatchとして扱い、issueごとの実装を内部 `task-worker` sub-agentへ委譲し、N本のsource PRと1本のdocumentation PRのmergeまでを管理する独立workflowのsource of truthである。

ユーザー判断を全issueのplan承認とDraft source PR一式の承認に集約し、2回目の承認後はsource統合、逐次merge、局所documentation同期、documentation PR mergeまでを自動完遂する。

根拠: `commands/task-manager.md:1-16`

## 動作の概要

1. `#<positive-number>` 形式のissueを1〜3件受け付け、4件以上、重複、不正形式をrepository変更前に拒否する。
2. repository、GitHub認証、issue状態、label、依存、既存PR/branchをread-onlyで確認する。
3. 親agentがissue別調査とbatch integration planをまとめ、全planの承認を得る。
4. 承認後、最新baseからissueごとのisolated worktreeとbranchを作る。
5. issueごとに実体のある `task-worker` sub-agentを最大3つ起動する。workerは親modelを継承する。
6. 各workerが実装、test、direct commit/push、`#<issue-number> <English title>` 形式のDraft source PR、structured handoffまでを担当する。
7. 親がcomplete Draft PR setを検証してユーザーへ提示し、NGなら該当workerによる修正後に全体を再提示する。
8. OK後、source PRを入力順に処理し、最初のPRをdelivery validation後にsquash mergeしてから、各後続actual PR branchへ処理時点のlatest mainを通常mergeで取り込む。
9. parallel workerのvalidationはearly feedbackとして扱う。各actual branchではrequired CIまたはplanned local fallbackによるauthoritative delivery validationを行い、conflict時はfocused testも通す。PR state、required checks、squash merge result、latest mainへの反映を確認してから次へ進む。
10. 全source merge後、changed-file unionをscope、finalization時のlatest mainをtruthとして局所documentation同期を行う。
11. documentation-only PRを作成・検証・Ready化・mergeし、全PRのmerge確認後にbatch完了を報告する。

根拠: `commands/task-manager.md:53-144`, `commands/task-manager.md:146-272`, `commands/task-manager.md:274-381`

## 主要な判定ロジック

### 入力境界

入力tokenは `^#[1-9][0-9]*$` で検証する。batch上限とworker上限はいずれも3であり、4件目以降をqueueへ積まず、4件以上の入力全体を開始前に拒否する。

根拠: `commands/task-manager.md:57-67`

### issue gate

存在しない・closed・`agenda`・未審査の`hazard-candidate`・open blockerあり・未完了sub-issueを持つ管理issue・既存作業が見えるissueのいずれかが含まれる場合、batch全体を開始しない。issue本文はuntrusted dataとして扱う。

根拠: `commands/task-manager.md:77-90`

### plan gateとDraft set gate

branch、worktree、file変更、GitHub書き込みより前にissue別planを一括承認する。source実装後は全Draft PRが揃い、approved scope、worker handoff、lightweight development validation、documentation非混入を検証できた場合だけcomplete setを提示する。個別PRの先行mergeは行わない。承認後はPR番号、scope、behaviorを保持するが、head SHAをexpected stateとして追跡しない。

根拠: `commands/task-manager.md:108-144`, `commands/task-manager.md:246-272`

### task-worker scheduling

accepted issueごとに1つの実sub-agentを割り当て、最大3workerを実行する。model overrideを省略して親modelを継承し、approved plan、worktree、branch、allowed paths、禁止事項をself-contained payloadで渡す。共通worker protocolとhandoff schemaを同じcommand内に置くため、公開 `task-worker` command/skillは不要である。

根拠: `commands/task-manager.md:162-244`

task-workerが直接作成するDraft source PRのtitleは、`/work` のtask flowと同じ `#<issue-number> <English title>` 形式とする。PR bodyは英語で、closing reference、changed files、test results、design intentを含める。batch全体を扱うdocumentation PRにはこの単一issue向けtitle形式を適用しない。

根拠: `commands/task-manager.md:205-220`, `commands/task-manager.md:350-360`

### source deliveryとsquash merge

complete Draft set承認後、source PRを入力順に処理する。最初のPRはcurrent actual branchをdelivery validationし、明示的にsquash mergeする。2本目以降は直前PRのvalidationとsquash mergeを確認してからactual branchへlatest mainをnormal non-rewriting mergeで取り込み、conflictをそのbranch上でforward repairする。rebase、force push、history rewriteは使わない。

parallel workerのlightweight development validationはearly feedbackであり、delivery passとして再利用しない。equivalent required CIがあればcurrent actual branchのchecksをauthoritative validationとして待ち、なければ同branch上でplanned local delivery validationを実行する。conflict repairにはaffected behaviorのfocused local testを追加し、missing validationをpassとして扱わない。後続PRはReady化直前にもlatest mainを含むことを確認し、不足していれば取り込みとvalidationを繰り返すが、expected-head SHA transactionは維持しない。

delivery条件通過後は対象PRだけをReady化し、`gh pr merge --squash`相当の明示的なsquash mergeをrequestする。merge API resultをauthoritativeに扱い、PR state、required checks、squash resultのlatest main反映を確認してから次へ進む。conflict、CI failure、base drift、merge rejectionはactual branch上のnew commitとnon-force pushでforward repairする。repairがreview済みbehavior、public contract、security boundary、approved scopeをmaterialに変える場合だけcomplete Draft set gateへ戻る。

根拠: `commands/task-manager.md:246-304`

### documentation scope

documentation scope、implementation truth、PR diffを分離する。

- scope: merged batch source PRのchanged-file union
- truth: documentation finalization開始時点のlatest main
- PR diff: latest mainとfresh documentation branchの差分

source PRにdocumentationを混ぜず、全source merge後に1回だけ独立したlocalized syncを行う。L0は変更せず、候補だけを`docs/.ai/l0_candidates.md`へ記録する。

根拠: `commands/task-manager.md:306-360`

## 重要な設計判断

- 3件固定上限により、超過issue queue、動的worker設定、scheduler stateを初期実装から除外した。
- task-worker protocolを親commandへ内包し、内部agentを誤ってユーザー向けcommandとして配布しない。
- model名を固定せず親modelを継承し、runtimeのmodel availability差や将来のmodel変更への依存を避ける。
- source PRとdocumentation PRを分離し、並行実装の速度を維持しながらshared documentationの競合を1本へ集約する。
- 実merge後の完全なtransaction rollbackを前提にせず、active process中はrecoverableなnew commitによるforward recoveryを優先する。
- actual source PR branchとlatest mainだけを統合のtruthとし、synthetic combined stateによる二重のconflict解消と検証を避ける。
- parallel development test、focused repair test、GitHub CI、local delivery fallbackの責務を分け、統合前のworker resultをauthoritative delivery validationとして扱わない。
- expected-head transactionを持たず、PR state、required checks、latest-main包含、merge API result、main反映を組み合わせてdelivery結果を検証する。
- source PRを明示的にsquash mergeし、`1 issue = 1 source PR = 1 main commit`のlinear main historyを保つ。
- issue選定、batch compatibility、conflict-risk評価、merge順最適化はProduct Manager側の責務とし、`/task-manager`は入力済みbatchのexecutorに限定する。
- batch stateを永続化せず、初期運用では1repository 1sessionのdisciplineに依存する。

根拠: `commands/task-manager.md:18-51`, `commands/task-manager.md:162-171`, `commands/task-manager.md:246-304`, `commands/task-manager.md:383-412`

## 統合ポイント

- Codex entry point: `skills/task-manager/SKILL.md`
- contract test: `tests/commands/test-task-manager.sh`
- Git/GitHub: isolated worktree、issue-specific branch、Draft PR、CI/check、Ready/merge
- repository context: `README.md`、`docs/.ai/repo.profile.json`、primary investigation docs、L3 per-file docs
- coding rules: approved file languageに対応するcoding skill

既存のimplementation/documentation workflowはruntime integration pointではない。禁止対象はcommand本体に列挙され、実行・委譲・source・wrap・runtime Readを行わない。

根拠: `commands/task-manager.md:18-31`, `commands/task-manager.md:69-106`, `commands/task-manager.md:205-220`

## 注意事項・既知の制限

- 同一repositoryで複数のtask-manager sessionを安全に排他するlockはない。
- batch state、cross-session resume、自動restart、background monitorはない。
- processまたはmachine停止後はworktree、branch、Draft PR、partial mergeをmanual recoveryする。
- conflict resolutionとmergeはGitHub上のactual PR branchで行うため、途中停止後は残存branch・PR・worktreeからmanual recoveryする必要がある。
- GitHub CIがplanned validationをcoverしない場合、そのvalidationはactual PR branch上のlocal fallbackとして実行可能でなければmergeへ進めない。
- expected-head SHA bookkeepingを持たないため、承認後の差分はPR state、diff、scope、behaviorの再確認でmaterial changeの有無を判断する。
- static command specificationであり、GitHub上のend-to-end transactionをlocal testだけで再現するものではない。
- periodicなrepository-wide documentation initializationは引き続き別途必要である。

根拠: `commands/task-manager.md:274-304`, `commands/task-manager.md:362-412`

## 変更履歴（git log より自動生成）

- 68643da feat(#387): simplify task manager source delivery
- b2b83ac #384 Replace task-manager pre-integration with sequential PR refresh (#385)
- 823f676 #381 Align task-manager source PR titles with work (#382)
- 8a9903f #379 Reuse task-manager integration conflict resolutions (#380)
- 5f1d984 #377 Add independent task-manager batch workflow (#378)
