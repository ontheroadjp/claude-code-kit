# /git-pr-merge

ユーザーがレビュー承認した1本のpull requestを、最新 `main` 上で検証し、明示的なsquash mergeで安全にdeliveryするworkflowです。

```text
/git-pr-merge #123
```

standalone invocationと、`/task-manager`からのdelegated invocationを受け付けます。このworkflowはPRの実装・レビュー自体を代替せず、承認済みheadからdeliveryまでの同一性と安全性を管理します。

## 呼び出しcontext

### standalone invocation

1. 引数が `^#[1-9][0-9]*$` に一致する単一PR番号であることを確認する。不正または複数ならusageを表示して終了する。
2. `gh pr view` でnumber、URL、title、state、isDraft、baseRefName、headRefName、headRefOid、headRepositoryOwner、changed filesをread-only取得する。
3. PRがopen、baseが`main`、同一repositoryのhead branchであることを確認する。
4. PR URL、title、Draft/Ready、current head SHA、changed filesを表示し、次を確認する。

> 表示したPRとcurrent head SHAをレビュー済みで、deliveryしてよいですか？

明確な承認がなければ書き込みを行わず終了する。承認されたcurrent head SHAを`approved_head_sha`、表示したdiffから確認した範囲・observable behaviorを`approved_scope_or_behavior`として保持し、承認済みfinal validation planを確定する。validation planが不明確なら承認前に具体化する。

### delegated invocation

`/task-manager`は次をすべて渡す。1項目でも欠ける場合は停止し、standalone approvalへ暗黙に切り替えない。

```text
pr_number: <number>
approved_head_sha: <full remote head SHA>
approved_scope_or_behavior: <reviewed files, scope, and observable behavior>
final_validation_plan: <required CI coverage and/or exact local commands>
approval_source: task-manager complete Draft set approval
owned_worktree: <absolute path or explicit permission to create an isolated repair worktree>
predecessor_approved_head: <chain position k≥2: #(k-1) の approved PR head SHA。position 1 / standalone: none>
full_validation_evidence: <optional; SHA-bound successful full-suite evidence>
```

`full_validation_evidence` と `predecessor_approved_head` は optional であり、欠如しても delegated context 不足とは扱わない（`predecessor_approved_head` は chain position 1 と standalone では `none`）。それ以外の delegated context が完全なら重複するユーザー承認を求めない。delegated approvalと validation evidence はこの1本のPRだけに適用し、別PRへ流用しない。

## 絶対不変条件

- local `main`をcheckout、edit、conflict repair、commit、pushに使用しない。
- `origin/main`はfetchし、actual PR head branchへnormal non-rewriting mergeするためだけに使用する。
- deliveryとconflict repairは、callerが所有を明示したcleanなPR worktree、またはこのPR専用に作成したisolated repair worktreeだけで行う。
- PR worktreeがdirty、unavailable、またはownership不明なら停止する。親のmain workspaceへfallbackしない。
- actual remote PR head branch以外へrepair commitをpushしない。`main`へ直接pushしない。
- force push、rebase、reset、history rewrite、merge commit方式、rebase merge方式を使用しない。
- branchとworktreeのcleanupはcallerに任せ、このworkflowでは削除しない。
- Draft/Readyの違いはReady transitionが必要かだけに影響する。latest-main refreshとfinal validationは常に行う。
- `predecessor_approved_head` を伴う delegated chain delivery では、対象PRは既にその predecessor head を内包している。sibling-worker divergence 由来のconflictは構造的に発生せず、Phase 3のconflict repairは想定外の外部変更専用に残る。

## Work-run event contract

共有契約は `commands/work.md` の「Work-run observability › 共有契約（work-run events を emit する全 command 共通）」に従う。helper のパスは delegated context の値、standalone 起動で work-run context がなければ emit しない。`/git-pr-merge` が emit する event:

- latest-main refresh: `main_refresh_result issue_number=<N> pr_number=<PR> outcome=<success|conflict|failed> conflict_count=<count>`
- current-head validation: `validation_result issue_number=<N> pr_number=<PR> outcome=<success|failed|stopped>`
- delivery: `delivery_result issue_number=<N> pr_number=<PR> outcome=<success|failed|stopped> [head_sha=<full-sha>]`

`predecessor_approved_head` を伴う delegated chain delivery では `#k` が既に `#(k-1)` を内包するため、`main_refresh_result` の構造上の期待値は `outcome=success conflict_count=0` である。`conflict_count>0` は想定外の外部変更を示す。

## Phase 0: read-only preflight

1. repository root、`gh auth status`、remote URLを確認する。
2. `git worktree list --porcelain`と各worktree statusを確認し、local `main` workspaceのpathを記録する。以降、そのpathをwrite operationのworking directoryにしない。
3. GitHubからcurrent PR metadata、remote head SHA、commits、diff、checksを再取得する。
4. PRがopen、baseが`main`、head branchが同一repositoryにあり、approved scope/behaviorと対応することを確認する。
5. current remote head SHAを`approved_head_sha`と比較する。

一致しない場合、Phase 1のknown commit判定へ進む前に、承認後にこのdelivery flowが作成したcommitだけで差分を説明できるか確認する。

## Phase 1: approved-head drift guard

### known delivery commit

known commitとして扱えるのは、active invocationが次の操作で実際に作成し、full SHA、parent SHA、目的、changed pathsをin-memoryに記録したcommitだけです。

- latest `origin/main`をactual PR branchへ取り込むnormal merge commit
- ユーザー承認済みの同一scope/behaviorを維持するconflict-repair commit
- failed validationを同一approved scope内で修正するため、このworkflow内でユーザー承認を得たrepair commit

author、message、branch名、時刻だけからknownと推測してはならない。invocation開始前から存在したcommit、外部push、記録とparent chainが一致しないcommitはunknownです。

current remote headがapproved headと異なる場合、`approved_head_sha..current_remote_head`の全commitが記録済みknown delivery commitで、first-parent/parent chainとchanged pathsも記録に一致するときだけ継続する。

### unknown commit

unknown commitを1件でも検出したら、書き込みとdeliveryを停止し、そのPRだけについて以下を表示する。

- previously approved head SHA
- current remote head SHA
- unknown commits
- changed filesとapproved scope/behaviorとの差分
- validationへの影響

> このPRのcurrent headを再レビューし、更新後のhead SHAを承認しますか？

明確な承認後だけ`approved_head_sha`とapproved scope/behaviorをcurrent remote stateへ更新する。delegated invocationでもcomplete batch全体へ戻さず、影響したPRだけを再承認対象とする。拒否または未回答なら停止する。

## Phase 2: owned worktreeとlatest-main refresh

1. caller指定worktreeがactual PR head branchをcheckout済みで、cleanかつownership明確なら使用する。
2. 使用できないがdelegated contextまたはstandalone approvalがisolated worktree作成を許可している場合、repository metadata配下の一意なpathにactual PR head branch専用worktreeを作成する。既存path/branchを上書きしない。
3. 上記を満たすworktreeを確保できなければ停止する。
4. worktree内でbranch、HEAD、remote tracking branch、clean statusを確認し、`git fetch origin main <head-ref>`を実行する。
5. fetch後のremote headにPhase 1 drift guardを再適用する。
6. latest `origin/main` SHAを記録し、actual PR branchが含んでいなければ`git merge --no-ff origin/main`相当のnormal non-rewriting mergeを行う。`predecessor_approved_head` を伴う delegated chain delivery では、`#k` がその predecessor head を既に内包しており（squash 済み `#(k-1)` と content 等価）このmergeはtree変化のないtrivial mergeになる。tree変化が生じた場合は想定外の外部変更としてPhase 3で扱う。
7. conflictがなければ生成されたmerge commitをknown delivery commitとして記録する。tree変化がなければ「known-empty delivery merge」として併せて記録する（Phase 4のevidence再利用で参照する）。

local `main`のcheckout状態、index、working tree、HEADは変更しない。

## Phase 3: conflict repairとscope guard

conflictが発生した場合はactual PR head branch上で解消し、そのbranchをcheckoutしたactual PR worktree内だけを使用する。

1. conflict pathsを列挙し、approved scope/behavior、public contract、security boundaryへの影響を評価する。
2. 同じobservable behaviorを保つ機械的修復だけを行う。
3. unmerged index entryとconflict markerがなく、`git diff --check`がpassすることを確認する。
4. affected behaviorにfocusedしたlocal testを実行する。
5. normal conflict-repair commitを作成し、SHA、parent、changed pathsをknown delivery commitとして記録する。
6. forceなしでactual PR head branchへpushする。

repairがobservable behavior、public contract、security boundary、approved scopeをmaterialに変える場合はcommit/push前に停止し、そのPRだけをユーザーレビューへ戻す。明確な承認後、修正と新headをapproved stateへ反映して続行する。

## Phase 4: current-head final validation

1. refresh/repair commitをforceなしでactual PR branchへpushする。
2. GitHubからcurrent remote headを再取得し、Phase 1 drift guardを適用する。
3. current post-refresh headに対応するGitHub checksを取得する。古いheadのcheck結果を再利用しない。
4. optional `full_validation_evidence` は次の全条件を満たす場合だけ再利用する。
   - `validation_scope` が exact `full`、`validation_outcome` が exact `success` で、全 field が存在する。
   - `validation_plan` が approved `final_validation_plan` と完全一致する。
   - `validated_head_sha` が current post-refresh remote head SHA と完全一致する。
   - `validated_base_sha` が Phase 2 で記録した current latest `origin/main` SHA と完全一致し、current head がその base を含む。
   - refresh merge、conflict repair、validation repair、external push により evidence 取得後の head/base が変化していない。
   - **delegated chain 例外**: caller が `predecessor_approved_head` を渡し、evidence の `validated_base_sha` がその `predecessor_approved_head` と完全一致する場合、直前の head/base 完全一致2条件を次の全てを満たすときに限り緩和する。緩和後も他の条件はそのまま要求する。
     - current post-refresh head が `predecessor_approved_head` と Phase 2 で記録した current latest `origin/main` の両方を含む。
     - `validated_head_sha` から current post-refresh head までの差分が、この invocation が Phase 2/3 で記録した known delivery commit だけで構成され、その全てが Phase 2 step 7 で「known-empty delivery merge」として記録されている（tree 変化ゼロ）。
     - unknown commit、実 conflict、tree 変化のある merge、external push がその区間に一切ない。
5. 4の全条件（または delegated chain 例外）を満たす場合、同じ full-suite local commands は再実行せず、SHA-bound evidence を authoritative local validation result として記録する。required checks は evidence で省略せず、current head に対する完了と success を従来どおり確認する。
6. evidence が absent、targeted-only、failed、incomplete、実行不能、plan mismatch、head mismatch、base mismatch、stale、または判定不能なら再利用しない（delegated chain 例外を満たす head/base mismatch は除く）。理由を記録し、以下の既存 authoritative current-head validation を実行する。
7. required CIがfinal validation planを完全にcoverする場合、そのcurrent headの完了を待ち、全required checkのsuccessを確認する。
8. 対応するCIがない場合、approved final validation commandsをactual PR worktreeで実行する。
9. CIがplanの一部だけをcoverする場合、current-head CI successに加え、missing validationをapproved local commandsで実行する。
10. missing、pendingのまま、skipped、neutral、対応不明、古いhead、実行不能なvalidationをpassとして扱わない。
11. failure修正がapproved scope内でも新しいrepair commitを必要とする場合、修正案と影響をユーザーへ提示し承認を得る。承認後にcommitをknown delivery commitとして記録し、Phase 4を最初から繰り返す。
12. merge直前に`origin/main`を再fetchし、actual PR headがcurrent latest `origin/main`を含むことを確認する。不足ならPhase 2へ戻る。再fetchでbase SHAが変わった場合、以前のevidenceは再利用せずPhase 2から再評価する。

## Phase 5: Ready transitionとexplicit squash merge

1. GitHubからstate、isDraft、base、remote head、checksを再取得し、open、base=`main`、approved-head drift guard通過、latest-main包含、current-head validation成功を確認する。
2. Draftなら`gh pr ready <PR>`でReady化する。既にReadyならこの操作だけをskipする。
3. `gh pr merge <PR> --squash`相当で明示的なsquash mergeをrequestする。auto-merge、merge commit、rebase mergeへ切り替えない。
4. base drift、check、state、branch protection等で拒否された場合は成功扱いせず、PR stateと`origin/main`を再取得してPhase 1またはPhase 2から再評価する。

## Phase 6: delivery verification

GitHubとgit remote stateを再取得し、次をすべて確認する。

- PR stateが`MERGED`である。
- GitHubが返すmerge commit OIDを取得できる。
- `origin/main`をfetch後、そのOIDがlatest `origin/main`に含まれる。
- merge resultがsquashであり、delivered PRに対するmain上の結果が1 commitである。
- squash resultのtree/diffがapproved PR changesを含む。
- delivery直前に記録したlatest-main SHAがdelivery結果の履歴へ含まれる。

1項目でも未確認ならsuccessを報告しない。確認できた場合だけPR URL、approved head、delivered remote head、squash SHA、latest-main SHA、CI/local validation結果、validation evidence の reused/executed と判定理由、known delivery commitsをcallerへ返す。

## 停止時の報告

停止時は、PR番号、停止phase、approved/current head、完了済みwrite、未完了条件、worktree pathを報告する。既にmerge済みのPRをrollbackせず、branch/worktree cleanupも行わない。
