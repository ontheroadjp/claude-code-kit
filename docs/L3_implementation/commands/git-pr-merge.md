# `/git-pr-merge`

## 目的・役割

ユーザーがreview済みの単一Draft/Ready PRをapproved head SHAで固定し、latest `origin/main`取り込み、current-head validation、explicit squash mergeまで安全にdeliveryするsource of truthである。standalone invocationと `/task-manager` からのdelegated invocationを受け付ける。

根拠: `commands/git-pr-merge.md:1-37`

## 動作の概要

1. standaloneではPR metadataとcurrent headを表示して明示承認を得る。delegatedではPR番号、approved head、scope/behavior、validation plan、approval source、owned worktreeを必須入力とする。
2. remote headをapproved headと比較し、active invocationがSHA・parent・目的・pathを記録したknown delivery commit以外のdriftをPR単位の再承認へ戻す。
3. owned PR worktreeまたはisolated repair worktreeでactual head branchへlatest mainをnormal mergeする。
4. conflictをactual branch上だけで修復し、material changeはcommit/push前に再承認する。
5. current post-refresh headに対応するCIを待ち、coverage不足分をapproved local validationで補う。
6. DraftだけReady化し、Draft/Readyの双方をexplicit squash mergeする。
7. merged state、squash OID、latest-main包含、1-commit resultを再取得して検証する。

根拠: `commands/git-pr-merge.md:13-37`, `commands/git-pr-merge.md:50-98`, `commands/git-pr-merge.md:100-143`

## 主要な判定ロジック

known commitはactive delivery flow自身がin-memoryに記録したlatest-main mergeと承認済みrepairだけであり、author、message、branch、timeから推測しない。unknown commitはbatch全体ではなく対象PRだけを止め、current headの明示承認後にapproved stateを更新する。

CIがvalidation planを完全coverするときだけCI単独をauthoritativeに扱う。CIなし・partial coverageではactual PR worktree上のapproved commandsを要求し、missing、pending、skipped、neutral、old-head resultはpassにしない。

根拠: `commands/git-pr-merge.md:60-86`, `commands/git-pr-merge.md:113-123`

## 重要な設計判断

- local `main` workspaceをcheckout、edit、repair、commit、pushに一切使わず、ownership不明時は停止する。
- rebase、reset、force push、history rewriteを使わず、actual PR branchへのforward-only commitで回復する。
- Draft/Ready差はReady transitionだけとし、refreshとvalidationを共通化する。
- branch/worktree cleanupはcaller責務に残す。

根拠: `commands/git-pr-merge.md:39-48`, `commands/git-pr-merge.md:88-111`, `commands/git-pr-merge.md:125-147`

## 統合ポイント

- user-facing Codex wrapper: `skills/git-pr-merge/SKILL.md`
- delegated caller: `commands/task-manager.md`
- contract test: `tests/commands/test-git-pr-merge.sh`
- Git/GitHub: owned worktree, remote PR head, checks, Ready transition, squash merge

## 注意事項・既知の制限

- active invocationのknown-commit stateは永続化しない。
- dirty/unavailable/unowned worktreeを自動cleanupまたはmain workspace fallbackしない。
- stopping後のbranch/worktree recoveryはcallerが行う。
