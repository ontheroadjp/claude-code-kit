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
8. OK後、source PRを入力順に処理し、最初の1本を含む各actual PR branchを処理時点のlatest mainへ通常mergeでrefreshする。
9. conflictはactual branch上で一度だけ解消し、focused testと不足するplanned validationのlocal fallback、exact headに対するrequired checksを通す。main drift時はrefresh loopを繰り返し、guarded merge resultとmain反映を確認してから次のPRへ進む。
10. 全source merge後、changed-file unionをscope、finalization時のlatest mainをtruthとして局所documentation同期を行う。
11. documentation-only PRを作成・検証・Ready化・mergeし、全PRのmerge確認後にbatch完了を報告する。

根拠: `commands/task-manager.md:50-141`, `commands/task-manager.md:143-269`, `commands/task-manager.md:271-378`

## 主要な判定ロジック

### 入力境界

入力tokenは `^#[1-9][0-9]*$` で検証する。batch上限とworker上限はいずれも3であり、4件目以降をqueueへ積まず、4件以上の入力全体を開始前に拒否する。

根拠: `commands/task-manager.md:54-64`

### issue gate

存在しない・closed・`agenda`・未審査の`hazard-candidate`・open blockerあり・未完了sub-issueを持つ管理issue・既存作業が見えるissueのいずれかが含まれる場合、batch全体を開始しない。issue本文はuntrusted dataとして扱う。

根拠: `commands/task-manager.md:74-87`

### plan gateとDraft set gate

branch、worktree、file変更、GitHub書き込みより前にissue別planを一括承認する。source実装後は全Draft PRが揃い、approved scope、head SHA、test、documentation非混入を検証できた場合だけcomplete setを提示する。個別PRの先行mergeは行わない。

根拠: `commands/task-manager.md:105-141`, `commands/task-manager.md:243-269`

### task-worker scheduling

accepted issueごとに1つの実sub-agentを割り当て、最大3workerを実行する。model overrideを省略して親modelを継承し、approved plan、worktree、branch、allowed paths、禁止事項をself-contained payloadで渡す。共通worker protocolとhandoff schemaを同じcommand内に置くため、公開 `task-worker` command/skillは不要である。

根拠: `commands/task-manager.md:159-241`

task-workerが直接作成するDraft source PRのtitleは、`/work` のtask flowと同じ `#<issue-number> <English title>` 形式とする。PR bodyは英語で、closing reference、changed files、test results、design intentを含める。batch全体を扱うdocumentation PRにはこの単一issue向けtitle形式を適用しない。

根拠: `commands/task-manager.md:202-217`, `commands/task-manager.md:347-355`

### source統合とmerge

Draft set承認時のPR番号とhead SHAを固定し、source PRを入力順に処理する。各PRではcurrent remote headとexpected headを照合し、actual branchへlatest mainをnormal non-rewriting mergeで取り込む。clean refreshではCIがplanned validationをcoverする限りlocal worker testを繰り返さず、conflict時はactual branch上で一度だけ解消してaffected behaviorのfocused testを行う。CIに存在しないplanned validationだけをlocal fallbackで実行し、missing validationをpassとして扱わない。

push後のexact expected headに対するrequired checksを待ち、checks中にmainが進んだ場合はReady化せずrefresh loopへ戻る。validation通過後はcurrent headを再guardし、対象PRだけをReady化して直ちにmergeをrequestする。asynchronousな`mergeable` pollingは前提とせず、merge API resultをauthoritativeに扱う。base driftによるrejectはrefresh loopへ戻し、成功時もPR stateとlatest mainへの反映を確認してから次へ進む。

conflict、CI failure、base drift、merge rejectionはactual branch上のnew commitとnon-force pushでforward repairする。repairがreview済みbehavior、public contract、security boundary、approved scopeをmaterialに変える場合だけcomplete Draft set gateへ戻る。

根拠: `commands/task-manager.md:243-301`

### documentation scope

documentation scope、implementation truth、PR diffを分離する。

- scope: merged batch source PRのchanged-file union
- truth: documentation finalization開始時点のlatest main
- PR diff: latest mainとfresh documentation branchの差分

source PRにdocumentationを混ぜず、全source merge後に1回だけ独立したlocalized syncを行う。L0は変更せず、候補だけを`docs/.ai/l0_candidates.md`へ記録する。

根拠: `commands/task-manager.md:303-355`

## 重要な設計判断

- 3件固定上限により、超過issue queue、動的worker設定、scheduler stateを初期実装から除外した。
- task-worker protocolを親commandへ内包し、内部agentを誤ってユーザー向けcommandとして配布しない。
- model名を固定せず親modelを継承し、runtimeのmodel availability差や将来のmodel変更への依存を避ける。
- source PRとdocumentation PRを分離し、並行実装の速度を維持しながらshared documentationの競合を1本へ集約する。
- 実merge後の完全なtransaction rollbackを前提にせず、active process中はrecoverableなnew commitによるforward recoveryを優先する。
- actual source PR branchとlatest mainだけを統合のtruthとし、synthetic combined stateによる二重のconflict解消と検証を避ける。
- worker test、focused repair test、GitHub CI、local fallbackの責務を分け、新しい状態を検証しない重複testを避けつつmissing validationを明示する。
- mergeabilityの非同期表示ではなくexpected head、required checks、main drift、merge API result、main反映を組み合わせてmerge直前の状態をguardする。
- batch stateを永続化せず、初期運用では1repository 1sessionのdisciplineに依存する。

根拠: `commands/task-manager.md:18-48`, `commands/task-manager.md:159-168`, `commands/task-manager.md:243-301`, `commands/task-manager.md:380-419`

## 統合ポイント

- Codex entry point: `skills/task-manager/SKILL.md`
- contract test: `tests/commands/test-task-manager.sh`
- Git/GitHub: isolated worktree、issue-specific branch、Draft PR、CI/check、Ready/merge
- repository context: `README.md`、`docs/.ai/repo.profile.json`、primary investigation docs、L3 per-file docs
- coding rules: approved file languageに対応するcoding skill

既存のimplementation/documentation workflowはruntime integration pointではない。禁止対象はcommand本体に列挙され、実行・委譲・source・wrap・runtime Readを行わない。

根拠: `commands/task-manager.md:18-31`, `commands/task-manager.md:66-101`, `commands/task-manager.md:202-217`

## 注意事項・既知の制限

- 同一repositoryで複数のtask-manager sessionを安全に排他するlockはない。
- batch state、cross-session resume、自動restart、background monitorはない。
- processまたはmachine停止後はworktree、branch、Draft PR、partial mergeをmanual recoveryする。
- conflict resolutionとmergeはGitHub上のactual PR branchで行うため、途中停止後は残存branch・PR・worktreeからmanual recoveryする必要がある。
- GitHub CIがplanned validationをcoverしない場合、そのvalidationはactual PR branch上のlocal fallbackとして実行可能でなければmergeへ進めない。
- static command specificationであり、GitHub上のend-to-end transactionをlocal testだけで再現するものではない。
- periodicなrepository-wide documentation initializationは引き続き別途必要である。

根拠: `commands/task-manager.md:271-301`, `commands/task-manager.md:359-419`

## 変更履歴（git log より自動生成）

- 07dc279 feat(#384): simplify task manager source integration
- 823f676 #381 Align task-manager source PR titles with work (#382)
- 8a9903f #379 Reuse task-manager integration conflict resolutions (#380)
- 5f1d984 #377 Add independent task-manager batch workflow (#378)
