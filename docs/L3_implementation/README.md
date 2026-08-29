# `README.md`

## Unified work entry

Features・Usage・Design Principles は `/work` を1〜3 issue の唯一の implementation entry として説明する。`/work` は atomic preflight、one-time project context、single task/patch routing、multi-issue task-manager delegation、final cleanup を所有する。`/task-manager` は internal orchestrator であり、delegated `/task` workers の independent plan/Ready PR approvals と fixed-order delivery だけを担う。

根拠: `README.md:55-77`, `README.md:138-170`, `README.md:200-218`

## 目的・役割

repositoryの公開入口として、project philosophy、利用可能なcommand、installation、usage、local verification、設計原則、構造を一覧化する。

根拠: `README.md:1-167`

## 動作の概要

- Core DesignでRepository Normalization、Issue-driven Development、Deterministic Workflow、Agentic Judgmentの組み合わせを説明する。
- documentation structure、implementation work contract、implementation workflowを主要な固定点とし、solution設計をagent、direction/approvalを人間へ割り当てる。
- Deterministic Fast Path、Agentic Fallback、Observability-driven Improvementの関係を初見ユーザー向けに要約する。
- Features tableで `/task-manager` をuser-provided batch executor、`/git-pr-merge` をreviewed PR delivery workflowとして公開する。
- Usageでstandalone PR deliveryとtask-managerからの逐次委譲を説明する。
- local verificationに両workflowのcontract testを掲載する。
- Design Principlesでapproved head SHA、owned PR worktree、current-head validation、explicit squash mergeの境界を固定する。

根拠: `README.md:1-53`, `README.md:55-85`, `README.md:138-218`

## 重要な設計判断

READMEはL0のplatform-independentな思想を短く提示した後、現行commandとoperationへ接続する。`/work`と`/task`はready PR作成で完了し、mergeは自動化しない。review後のdeliveryはユーザーが明示的に `/git-pr-merge` を起動する別責務とする。`/task-manager`だけはcomplete Draft set approvalをdelegated approval contextとして同workflowを利用する。

## 統合ポイント

- command specifications: `commands/*.md`
- Codex wrappers: `skills/*/SKILL.md`
- command tests: `tests/commands/*.sh`
- installer: `install.sh`

## 注意事項・既知の制限

READMEは概要であり、実行時の完全な安全条件は各command specificationをsource of truthとする。

## 変更履歴（git log より自動生成）

- f52dd59 feat(#400): unify work entry point
- c9e5dff docs(#393): clarify project design philosophy
- 149bedd docs: initialize project documentation (init-docs) (#392)
- a23fda3 #389 Add reusable reviewed PR delivery workflow (#391)
- 6dc29d5 #387 Simplify task-manager source delivery (#388)
- b2b83ac #384 Replace task-manager pre-integration with sequential PR refresh (#385)
- 8a9903f #379 Reuse task-manager integration conflict resolutions (#380)
- 5f1d984 #377 Add independent task-manager batch workflow (#378)
- 0bfdaf3 #372 Move status line setup scripts into scripts directory (#373)
- 3fa2055 #370 Add idempotent Codex status line setup (#371)
- 396533d #367 Automate CLAUDE.md/AGENTS.md global symlinks in install.sh (#368)
