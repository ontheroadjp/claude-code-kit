# `/git-pr-merge`

## 目的・役割

ユーザーがreview済みの単一Draft/Ready PRをapproved head SHAで固定し、latest `origin/main`取り込み、current-head validation、explicit squash mergeまで安全にdeliveryするsource of truthである。standalone invocationと `/task-manager` からのdelegated invocationを受け付ける。

根拠: `commands/git-pr-merge.md:1-38`

## 動作の概要

1. standaloneではPR metadataとcurrent headを表示して明示承認を得る。delegatedではPR番号、approved head、scope/behavior、validation plan、approval source、isolated delivery worktree作成許可を必須入力とし、optional で `full_validation_evidence` を受け取る。
2. remote headをapproved headと比較し、active invocationがSHA・parent・目的・pathを記録したknown delivery commit以外のdriftをPR単位の再承認へ戻す。
3. 自分で作成したisolated worktreeでactual head branchへlatest mainをnormal mergeする。delegated deliveryでは対象PRが起動時点のlatest `origin/main`から分岐しているため、通常このmergeはno-opまたはclean fast-forward（`main_refresh_result` は `conflict_count=0` が期待値）になる。
4. conflictをactual branch上だけで修復し、material changeはcommit/push前に再承認する。delegated deliveryでconflictは起動後の外部変更時のみ発生する。
5. optional full-suite evidence が exact plan・successful full scope・current head SHA・current latest-main base SHA のすべてに一致する場合（#404 の厳密一致）、同じ local full suite の再実行を省略する。満たさなければ current post-refresh headに対応するCIを待ち、coverage不足分をapproved local validationで補う。
6. DraftだけReady化し、Draft/Readyの双方をexplicit squash mergeする。
7. merged state、squash OID、latest-main包含、1-commit resultを再取得して検証する。

根拠: `commands/git-pr-merge.md:13-38`, `commands/git-pr-merge.md:51-109`, `commands/git-pr-merge.md:111-149`

## 主要な判定ロジック

known commitはactive delivery flow自身がin-memoryに記録したlatest-main mergeと承認済みrepairだけであり、author、message、branch、timeから推測しない。unknown commitはbatch全体ではなく対象PRだけを止め、current headの明示承認後にapproved stateを更新する。

CIがvalidation planを完全coverするときだけCI単独をauthoritativeに扱う。CIなし・partial coverageではactual PR worktree上のapproved commandsを要求し、missing、pending、skipped、neutral、old-head resultはpassにしない。

delegated caller から受け取る `full_validation_evidence` は optional である。再利用には `validation_scope=full`、`validation_outcome=success`、approved plan との完全一致、current post-refresh remote head と `validated_head_sha` の完全一致、current latest `origin/main` と `validated_base_sha` の完全一致をすべて要求する（#404 の厳密一致）。missing、targeted-only、failed、incomplete、stale、plan/head/base mismatch、判定不能は理由を記録して既存 authoritative validation にフォールバックする。required checks は evidence で省略しない。

根拠: `commands/git-pr-merge.md:61-97`, `commands/git-pr-merge.md:124-142`

## 重要な設計判断

- local `main` workspaceをcheckout、edit、repair、commit、pushに一切使わず、ownership不明時は停止する。
- rebase、reset、force push、history rewriteを使わず、actual PR branchへのforward-only commitで回復する。
- Draft/Ready差はReady transitionだけとし、refreshとvalidationを共通化する。
- branch/worktree cleanupはcaller責務に残す。
- evidence reuse は「同一 head を同一 base 上で同一 full plan により検証済み」という狭い最適化に限定し、少しでも state が変われば安全側の再検証に戻す（#404）。#412 の delegated chain 例外（`predecessor_approved_head` で head/base SHA 一致を緩和）は、実測で approved-head chain 自体が squash delivery と分岐 conflict を起こすことが判明したため、chain もろとも撤回した（issue #414）。delegated worker は latest `origin/main` から分岐するので base が本物の latest-main と一致し、緩和なしで evidence を再利用できる。

根拠: `commands/git-pr-merge.md:40-49`, `commands/git-pr-merge.md:99-122`, `commands/git-pr-merge.md:124-148`

## 統合ポイント

- user-facing Codex wrapper: `skills/git-pr-merge/SKILL.md`
- delegated caller: `commands/task-manager.md`
- evidence producer: 全 delegated `commands/task.md` worker（issue につき1回、latest `origin/main` 上で）
- contract test: `tests/commands/test-git-pr-merge.sh`
- Git/GitHub: owned worktree, remote PR head, checks, Ready transition, squash merge

## 注意事項・既知の制限

- active invocationのknown-commit stateは永続化しない。
- dirty/unavailable/unowned worktreeを自動cleanupまたはmain workspace fallbackしない。
- stopping後のbranch/worktree recoveryはcallerが行う。
- delegated deliveryでは `/task-manager` が worktree を渡さないため、常にこのworkflowがisolated delivery worktreeを作成する。

## 変更履歴（git log より自動生成）

- a405d08 feat(#412): chain delegated workers on the predecessor's approved PR head
- abe4573 feat(#410): consolidate the shared work-run event contract into work.md (#411)
- 29b88f2 feat(#404): reuse SHA-bound full-suite validation (#405)
- 9fc5b9a feat(#401): add structured work run observability (#403)
- a23fda3 #389 Add reusable reviewed PR delivery workflow (#391)

## Work-run observability

共有契約は `commands/work.md`「Work-run observability › 共有契約」を参照。delegated work-run contextがある場合、`main_refresh_result`（conflict count 含む）・`validation_result`・`delivery_result` をこのworkflowが所有するeventとして emit する。standalone 起動で context がなければ emit しない。

根拠: `commands/git-pr-merge.md:51-59`
