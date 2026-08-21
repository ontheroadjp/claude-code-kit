# `tests/commands/test-task-manager.sh`

## 目的・役割

`commands/task-manager.md` と `skills/task-manager/SKILL.md` の安全上・設計上重要な契約を固定文字列で検証するshell testである。Markdown workflowは直接実行可能なprogramではないため、repository既存のcommand contract test方式を踏襲する。

根拠: `tests/commands/test-task-manager.sh:1-9`, `tests/commands/test-task-manager.sh:49-123`

## 動作の概要

1. repository rootからcommandとskillのpathを解決する。
2. `assert_exists` で両fileの存在を確認する。
3. `assert_contains` で必須契約の存在を確認する。
4. `assert_absent` で既存workflowへのdelegate表現がないことを確認する。
5. failure数を集計し、1件以上ならexit 1、すべてpassならexit 0を返す。

根拠: `tests/commands/test-task-manager.sh:5-47`, `tests/commands/test-task-manager.sh:134-139`

## 主要な検証契約

- single issueおよび3 issueのusage
- `#<positive-number>` token形式、1〜3件受付、4件以上・重複拒否
- 4件目以降のqueue非導入
- plan承認前のread-only boundary
- task-workerが実sub-agentであり、最大3worker、親model継承であること
- self-contained worker payload、structured handoff、direct Draft PR作成
- source PR titleの `#<issue-number> <English title>` 形式
- complete Draft PR setのreview loop
- approved PR set・scope・behavior保持、入力順逐次delivery、最初のPR完了後の後続actual branch refresh、対象PRだけのReady化
- latest mainのnormal merge、actual branch上でのforward conflict repair、focused test
- parallel validationのearly-feedback限定、required CIまたはplanned local delivery fallback、missing validation拒否
- expected-head SHA transactionの不在、latest-main包含、required checks、authoritative merge result、main反映確認
- 明示的squash mergeと`1 issue = 1 source PR = 1 main commit`のlinear history
- issue選定・batch compatibility・merge順最適化などProduct Manager責務の非導入
- synthetic integration worktree、resolution artifact、preimage、patch replayが存在しないこと
- merged batch changed-file unionとlatest mainによるlocalized documentation sync
- 第3の承認なしでdocumentation PRをmergeすること
- partial completionをsuccessにしないこと
- batch state、resume、distributed lock、GitHub Actions state managerの非導入
- 既存workflow commandへのruntime依存禁止
- `task-worker`を公開command/skillにしないこと

根拠: `tests/commands/test-task-manager.sh:52-132`

## 重要な設計判断

agent runtimeやGitHubへ実際のbranch/PR/mergeを作るend-to-end testではなく、Claude CodeとCodexが共通で読むMarkdown source of truthのcontractを直接検証する。これにより外部stateを変更せず、workflowの重要境界に対するregressionを高速に検出する。

禁止対象workflow名そのものは独立性説明に必要なため、単純な名称不在ではなく、delegateを意味する具体的表現の不在を検証する。

根拠: `tests/commands/test-task-manager.sh:73-123`

## 統合ポイント

- test target: `commands/task-manager.md`, `skills/task-manager/SKILL.md`
- execution: `bash tests/commands/test-task-manager.sh`
- lint: `shellcheck -x tests/commands/test-task-manager.sh`
- shell syntax: `bash -n tests/commands/test-task-manager.sh`

## 注意事項・既知の制限

- 固定文字列testであり、sub-agent schedulingやGitHub mergeを実行時に検証しない。
- 意味を保った文言変更でもassertion更新が必要になる場合がある。
- literal Markdown backtickとinstalled `~` pathに対するShellCheck warningは、理由付きで限定的に抑制する。

根拠: `tests/commands/test-task-manager.sh:1-3`, `tests/commands/test-task-manager.sh:91-107`, `tests/commands/test-task-manager.sh:119-132`

## 変更履歴（git log より自動生成）

- 07dc279 feat(#384): simplify task manager source integration
- 823f676 #381 Align task-manager source PR titles with work (#382)
- 8a9903f #379 Reuse task-manager integration conflict resolutions (#380)
- 5f1d984 #377 Add independent task-manager batch workflow (#378)
