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
8. OK後、approved headを最新mainへ重ねたcombined resultを検証する。integration conflictはsession-localなresolution artifactとして記録し、後続PRの実branch refreshで同等性を証明できる場合だけ解消判断をreplayする。
9. source PRを入力順に1本ずつReady化・mergeする。各実branchは最新mainへ通常mergeでrefreshし、artifactをreplayした場合もfocused checksとmergeabilityを再検証する。
10. 全source merge後、changed-file unionをscope、finalization時のlatest mainをtruthとして局所documentation同期を行う。
11. documentation-only PRを作成・検証・Ready化・mergeし、全PRのmerge確認後にbatch完了を報告する。

根拠: `commands/task-manager.md:48-139`, `commands/task-manager.md:141-265`, `commands/task-manager.md:267-383`

## 主要な判定ロジック

### 入力境界

入力tokenは `^#[1-9][0-9]*$` で検証する。batch上限とworker上限はいずれも3であり、4件目以降をqueueへ積まず、4件以上の入力全体を開始前に拒否する。

根拠: `commands/task-manager.md:52-62`

### issue gate

存在しない・closed・`agenda`・未審査の`hazard-candidate`・open blockerあり・未完了sub-issueを持つ管理issue・既存作業が見えるissueのいずれかが含まれる場合、batch全体を開始しない。issue本文はuntrusted dataとして扱う。

根拠: `commands/task-manager.md:72-85`

### plan gateとDraft set gate

branch、worktree、file変更、GitHub書き込みより前にissue別planを一括承認する。source実装後は全Draft PRが揃い、approved scope、head SHA、test、documentation非混入を検証できた場合だけcomplete setを提示する。個別PRの先行mergeは行わない。

根拠: `commands/task-manager.md:103-139`, `commands/task-manager.md:241-265`

### task-worker scheduling

accepted issueごとに1つの実sub-agentを割り当て、最大3workerを実行する。model overrideを省略して親modelを継承し、approved plan、worktree、branch、allowed paths、禁止事項をself-contained payloadで渡す。共通worker protocolとhandoff schemaを同じcommand内に置くため、公開 `task-worker` command/skillは不要である。

根拠: `commands/task-manager.md:157-239`

task-workerが直接作成するDraft source PRのtitleは、`/work` のtask flowと同じ `#<issue-number> <English title>` 形式とする。PR bodyは英語で、closing reference、changed files、test results、design intentを含める。batch全体を扱うdocumentation PRにはこの単一issue向けtitle形式を適用しない。

根拠: `commands/task-manager.md:200-215`, `commands/task-manager.md:361-369`

### source統合とmerge

Draft set承認時のPR番号とhead SHAを固定し、latest mainへ入力順に重ねたcombined resultでintegration testを行う。integration conflictごとにbase、approved heads、merge order、conflicted paths、index stage blobまたは`AUTO_MERGE` preimage、resolution-only patch、resolved blob、validated combined tree hashをsession-local artifactへ記録する。no-conflict batchではartifactを作らない。

predecessor merge後に後続PRの実branchをlatest mainへ通常mergeして同じconflictが発生した場合、path set、preimage/context、approved head、merge orderが一致するartifactだけを候補にする。patchは`git apply --check`後に記録pathだけへ適用し、unmerged entry・marker不在、`git diff --check`、resolved blob、validated treeとの一致またはbase refreshだけで説明できる差分、focused checksを検証する。成功時もnormal repair commitをforceなしでpushし、head、checks、mergeabilityを再取得する。

contextやtree resultが一致しない場合はpatch結果を残さずcleanなmergeから既存forward repairを行う。実mergeは引き続き入力順で、対象PRだけをReady化して直ちにmergeし、main反映を確認してから次へ進む。materialなsource変更が必要な場合だけDraft set gateへ戻る。

根拠: `commands/task-manager.md:267-315`

### documentation scope

documentation scope、implementation truth、PR diffを分離する。

- scope: merged batch source PRのchanged-file union
- truth: documentation finalization開始時点のlatest main
- PR diff: latest mainとfresh documentation branchの差分

source PRにdocumentationを混ぜず、全source merge後に1回だけ独立したlocalized syncを行う。L0は変更せず、候補だけを`docs/.ai/l0_candidates.md`へ記録する。

根拠: `commands/task-manager.md:296-350`

## 重要な設計判断

- 3件固定上限により、超過issue queue、動的worker設定、scheduler stateを初期実装から除外した。
- task-worker protocolを親commandへ内包し、内部agentを誤ってユーザー向けcommandとして配布しない。
- model名を固定せず親modelを継承し、runtimeのmodel availability差や将来のmodel変更への依存を避ける。
- source PRとdocumentation PRを分離し、並行実装の速度を維持しながらshared documentationの競合を1本へ集約する。
- 実merge後の完全なtransaction rollbackを前提にせず、active process中はrecoverableなnew commitによるforward recoveryを優先する。
- integration worktreeと実PR branch refreshは目的が異なるため両方を維持し、再利用するのは同等性を検証できたconflict resolution decisionだけとする。
- resolution artifactをsession-localかつbatch固有に限定し、repository-global `rerere`やpersistent stateによる誤ったcross-session reuseを避ける。
- batch stateを永続化せず、初期運用では1repository 1sessionのdisciplineに依存する。

根拠: `commands/task-manager.md:18-46`, `commands/task-manager.md:157-166`, `commands/task-manager.md:280-315`, `commands/task-manager.md:383-422`

## 統合ポイント

- Codex entry point: `skills/task-manager/SKILL.md`
- contract test: `tests/commands/test-task-manager.sh`
- Git/GitHub: isolated worktree、issue-specific branch、Draft PR、CI/check、Ready/merge
- repository context: `README.md`、`docs/.ai/repo.profile.json`、primary investigation docs、L3 per-file docs
- coding rules: approved file languageに対応するcoding skill

既存のimplementation/documentation workflowはruntime integration pointではない。禁止対象はcommand本体に列挙され、実行・委譲・source・wrap・runtime Readを行わない。

根拠: `commands/task-manager.md:18-31`, `commands/task-manager.md:64-101`, `commands/task-manager.md:200-215`

## 注意事項・既知の制限

- 同一repositoryで複数のtask-manager sessionを安全に排他するlockはない。
- batch state、cross-session resume、自動restart、background monitorはない。
- processまたはmachine停止後はworktree、branch、Draft PR、partial mergeをmanual recoveryする。
- resolution artifactはcurrent session終了後のresumeには利用できず、通常cleanupで削除する。
- patch applicabilityまたはtree equivalenceを完全に説明できないconflictはautomatic reuseせず、通常のforward repairが必要になる。
- static command specificationであり、GitHub上のend-to-end transactionをlocal testだけで再現するものではない。
- periodicなrepository-wide documentation initializationは引き続き別途必要である。

根拠: `commands/task-manager.md:304-315`, `commands/task-manager.md:373-422`

## 変更履歴（git log より自動生成）

- a634701 fix(#381): align task manager source PR titles
- 8a9903f #379 Reuse task-manager integration conflict resolutions (#380)
- 5f1d984 #377 Add independent task-manager batch workflow (#378)
