# `tests/commands/test-task-manager.sh`

## 目的・役割

`commands/task-manager.md`と`skills/task-manager/SKILL.md`のstreaming issue pipeline契約を固定文字列で検証するshell contract testである。

根拠: `tests/commands/test-task-manager.sh:1-42`

## 動作の概要

input boundary、read-only preflight、issue-specific state、non-blocking approval、structured investigation handoff、worker continuity、work-equivalent PR、fixed-order delivery、per-PR documentation refresh、localized reapproval、skill wiringを検証する。

根拠: `tests/commands/test-task-manager.sh:44-116`

## 主要な検証契約

- 1〜3 issue、duplicate/invalid/4件以上の拒否
- 8つのindependent issue stateとarrival-order result handling
- plan/Draft complete-set barrierの不在
- parent investigation evidenceの全fieldと、再read理由の限定
- same-worker continuationとreplacement handoff
- source、test、L3、aggregate docs、READMEを含むissue PR
- approved後のdelivery eligibility保持とinput-order merge
- latest-main、current documentation truth、authoritative current-head validation
- final batch documentation PRの不在
- mechanical refreshは再承認不要、material changeはaffected PRだけreset

根拠: `tests/commands/test-task-manager.sh:44-107`

## 重要な設計判断

orchestrationの挙動をstatic contractとして検証し、single-PR delivery mechanics自体は `test-git-pr-merge.sh`に委ねる。禁止済みのcomplete-set barrierとbatch docs phaseはabsence assertionで再導入を防ぐ。

## 統合ポイント

- targets: `commands/task-manager.md`, `skills/task-manager/SKILL.md`
- related delivery test: `tests/commands/test-git-pr-merge.sh`
- execution: `bash tests/commands/test-task-manager.sh`
- lint: `shellcheck -x tests/commands/test-task-manager.sh`

## 注意事項・既知の制限

sub-agent schedulingやGitHub deliveryを実行するend-to-end testではなく、workflow textのstatic contract testである。

## 変更履歴（git log より自動生成）

- 05fbd40 fix(#398): preserve task-manager test executable mode
- f3be053 feat(#398): stream task-manager issue pipelines
- a9fbb5f fix(#369): generate conventional task PR titles (#395)
- a23fda3 #389 Add reusable reviewed PR delivery workflow (#391)
- 6dc29d5 #387 Simplify task-manager source delivery (#388)
- b2b83ac #384 Replace task-manager pre-integration with sequential PR refresh (#385)
- 823f676 #381 Align task-manager source PR titles with work (#382)
- 8a9903f #379 Reuse task-manager integration conflict resolutions (#380)
- 5f1d984 #377 Add independent task-manager batch workflow (#378)
