# `/git-pr-merge`

## 目的・役割

ユーザーがreview済みの単一Draft/Ready PRをapproved head SHAで固定し、latest `origin/main`取り込み、current-head validation、explicit squash mergeまで安全にdeliveryするsource of truthである。standalone invocationと `/task-manager` からのdelegated invocationを受け付ける。

根拠: `commands/git-pr-merge.md:1-37`

## 動作の概要

1. standaloneではPR metadataとcurrent headを表示して明示承認を得る。delegatedではPR番号、approved head、scope/behavior、validation plan、approval source、owned worktreeを必須入力とし、chain position k≥2 では `predecessor_approved_head` を optional で受け取る。
2. remote headをapproved headと比較し、active invocationがSHA・parent・目的・pathを記録したknown delivery commit以外のdriftをPR単位の再承認へ戻す。
3. owned PR worktreeまたはisolated repair worktreeでactual head branchへlatest mainをnormal mergeする。`predecessor_approved_head` を伴うchain deliveryでは対象PRが既にそのpredecessorを内包しており、このmergeはtree変化のないtrivial merge（`main_refresh_result` は `conflict_count=0` が期待値）で、tree変化ゼロなら「known-empty delivery merge」として記録する。
4. conflictをactual branch上だけで修復し、material changeはcommit/push前に再承認する。chain deliveryでsibling divergence conflictは構造的に発生しない。
5. optional full-suite evidence が exact plan・successful full scope・current head SHA・current latest-main base SHA のすべてに一致する場合、同じ local full suite の再実行を省略する。delegated chain 例外として、evidence の `validated_base_sha` が `predecessor_approved_head` と一致し、`validated_head_sha` から current head までの差分が記録済みの known-empty delivery merge だけなら、head/base SHA 完全一致を緩和して再利用する（他条件と required checks はそのまま）。いずれも満たさなければ current post-refresh headに対応するCIを待ち、coverage不足分をapproved local validationで補う。
6. DraftだけReady化し、Draft/Readyの双方をexplicit squash mergeする。
7. merged state、squash OID、latest-main包含、1-commit resultを再取得して検証する。

根拠: `commands/git-pr-merge.md:13-39`, `commands/git-pr-merge.md:52-112`, `commands/git-pr-merge.md:114-158`

## 主要な判定ロジック

known commitはactive delivery flow自身がin-memoryに記録したlatest-main mergeと承認済みrepairだけであり、author、message、branch、timeから推測しない。unknown commitはbatch全体ではなく対象PRだけを止め、current headの明示承認後にapproved stateを更新する。

CIがvalidation planを完全coverするときだけCI単独をauthoritativeに扱う。CIなし・partial coverageではactual PR worktree上のapproved commandsを要求し、missing、pending、skipped、neutral、old-head resultはpassにしない。

delegated caller から受け取る `full_validation_evidence` は optional である。再利用には `validation_scope=full`、`validation_outcome=success`、approved plan との完全一致、current post-refresh remote head と `validated_head_sha` の完全一致、current latest `origin/main` と `validated_base_sha` の完全一致をすべて要求する。delegated chain 例外: `predecessor_approved_head` が渡され evidence の `validated_base_sha` がそれと一致する場合、head/base SHA 完全一致2条件を、current head が predecessor と latest main の両方を含み、かつ `validated_head_sha` から current head までが記録済み known-empty delivery merge のみで構成されるときに限り緩和する。missing、targeted-only、failed、incomplete、stale、（例外に該当しない）plan/head/base mismatch、判定不能は理由を記録して既存 authoritative validation にフォールバックする。required checks は evidence で省略しない。

根拠: `commands/git-pr-merge.md:63-99`, `commands/git-pr-merge.md:131-137`

## 重要な設計判断

- local `main` workspaceをcheckout、edit、repair、commit、pushに一切使わず、ownership不明時は停止する。
- rebase、reset、force push、history rewriteを使わず、actual PR branchへのforward-only commitで回復する。
- Draft/Ready差はReady transitionだけとし、refreshとvalidationを共通化する。
- branch/worktree cleanupはcaller責務に残す。
- evidence reuse は「同一 head を同一 base 上で同一 full plan により検証済み」という狭い最適化に限定し、少しでも state が変われば安全側の再検証に戻す。delegated chain 例外だけは、base が凍結された `predecessor_approved_head` で、head 差分が tree 変化ゼロの delivery-flow merge のみ、という厳密に検証可能な条件下で head/base SHA 一致を緩和する（chain では `#k` が `#(k-1)` を内包するため refresh merge が空になり、worker の up-front full-suite が結合状態の authoritative 検証になる — issue #412）。

根拠: `commands/git-pr-merge.md:41-51`, `commands/git-pr-merge.md:90-116`, `commands/git-pr-merge.md:126-152`

## 統合ポイント

- user-facing Codex wrapper: `skills/git-pr-merge/SKILL.md`
- delegated caller: `commands/task-manager.md`
- evidence producer: `commands/task.md` delegated first-delivery worker
- contract test: `tests/commands/test-git-pr-merge.sh`
- Git/GitHub: owned worktree, remote PR head, checks, Ready transition, squash merge

## 注意事項・既知の制限

- active invocationのknown-commit stateは永続化しない。
- dirty/unavailable/unowned worktreeを自動cleanupまたはmain workspace fallbackしない。
- stopping後のbranch/worktree recoveryはcallerが行う。
- delegated chain 例外は `predecessor_approved_head` が渡され、かつ head 差分が tree 変化ゼロの記録済み delivery merge のみのときだけ成立する。tree 変化のある merge・unknown commit・外部 push があれば通常の再検証に戻る。

## 変更履歴（git log より自動生成）

- 3aff0cc feat(#410): consolidate the shared work-run event contract into work.md
- 29b88f2 feat(#404): reuse SHA-bound full-suite validation (#405)
- 9fc5b9a feat(#401): add structured work run observability (#403)
- a23fda3 #389 Add reusable reviewed PR delivery workflow (#391)

## Work-run observability

共有契約は `commands/work.md`「Work-run observability › 共有契約」を参照。delegated work-run contextがある場合、`main_refresh_result`（conflict count 含む）・`validation_result`・`delivery_result` をこのworkflowが所有するeventとして emit する。standalone 起動で context がなければ emit しない。

根拠: `commands/git-pr-merge.md:50-58`
