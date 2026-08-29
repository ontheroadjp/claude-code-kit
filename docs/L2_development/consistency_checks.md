# Consistency Checks

最終実行: 2026-08-21

## docs → 実体

### Command / skill paths

- `commands/` には README を除いて28個の command specification が存在する。
- `skills/` には28個の `SKILL.md` が存在し、command basename と1:1で対応する。
- `docs/.ai/repo.profile.json` の `active_commands` と `skills` は、この28件を漏れなく列挙する。

根拠: `commands/` 実体一覧、`skills/` 実体一覧、`docs/.ai/repo.profile.json:active_commands`、`docs/.ai/repo.profile.json:skills`

### Hooks

`install.sh` が symlink 対象とする top-level hook script は9本で、Repo Profile の `hooks` と一致する。`hooks/lib/` の3 helper は top-level 配置対象ではない。

根拠: `install.sh:20-45`, `hooks/` 実体一覧、`docs/.ai/repo.profile.json:hooks`

### Runtime / build / test commands

Repo Profile の commands はすべて実体に対応する。

| 分類 | Repo Profile の command | 実体 |
|---|---|---|
| install | `./install.sh` | executable installer |
| statusline | `./scripts/setup_statusline_for_claude.sh` | executable Claude installer |
| statusline | `./scripts/setup_statusline_for_codex.sh` | executable Codex installer |
| site | `cd site && npm ci` | CI install step |
| site | `cd site && npm run docs:dev` | `site/package.json:scripts.docs:dev` |
| site | `cd site && npm run docs:build` | package script and CI build step |
| site | `cd site && npm run docs:preview` | `site/package.json:scripts.docs:preview` |
| analyze | `python3 scripts/analyze_access.py --all` | access log aggregator |
| analyze | `python3 scripts/analyze_auto_approve.py --all` | auto-approve log aggregator |
| analyze | `python3 scripts/analyze_token_usage.py --all` | token-usage log aggregator |
| analyze | `python3 scripts/analyze_work_runs.py logs/work-runs` | logical work-run aggregator |
| shell lint | `shellcheck -x $(find ...)` | all shell scripts with CI exclusions |
| shell test | `bash tests/hooks/test-approval-hooks.sh` | hook safety contract |
| shell test | `bash tests/hooks/test-session-paths.sh` | session path resolution contract |
| shell test | `bash tests/commands/test-mtg.sh` | agenda / mtg contract |
| shell test | `bash tests/commands/test-coding-guidelines.sh` | coding guideline composition, routing, portability contract |
| shell test | `bash tests/commands/test-workflow-contracts.sh` | workflow responsibility boundary contract |
| shell test | `bash tests/commands/test-work-multi.sh` | isolated worktree contract |
| shell test | `bash tests/commands/test-task-manager.sh` | batch orchestration and delegated delivery contract |
| shell test | `bash tests/commands/test-git-pr-merge.sh` | approved-head and PR delivery safety contract |
| shell test | `bash tests/commands/test-hazard-workflows.sh` | hazard workflow routing contract |
| shell test | `bash tests/install/test-install.sh` | installer contract |
| shell test | `bash tests/install/test-setup-statusline-for-codex.sh` | Codex status line config contract |
| shell test | `bash tests/scripts/test-link-worktree-untracked.sh` | worktree lazy linker contract |
| shell test | `bash tests/scripts/test-rename-thread.sh` | transcript title update contract |
| shell test | `bash tests/scripts/test-worktree-status.sh` | worktree status filtering contract |
| shell test | `bash tests/scripts/test-work-run-events.sh` | work-run writer contract |
| Python test | `python3 -m pytest tests/scripts/` | analysis-script contract |

根拠: `docs/.ai/repo.profile.json:commands`, `site/package.json:4-8`, `.github/workflows/deploy.yml:31-37`, `commands/analyze-access.md:27-35`, `commands/analyze-auto-approve.md:28-36`, `commands/analyze-token-usage.md:27-35`, `tests/` 実体一覧

## repo.profile.json ↔ docs

- `doc_roots` の4 directory は実在し、L0、L1、L2、L3 の生成済み構造と一致する。
- `primary_docs.investigation` と `primary_docs.structure` は実在する。
- `commands` の全26項目は `operation_model.md`、`test.md`、`cicd.md` のいずれかで説明される。
- `active_commands` 28件、`skills` 28件、`hooks` 9件は実体一覧と一致する。

根拠: `docs/.ai/repo.profile.json`, `docs/L2_development/operation_model.md`, `docs/L2_development/test.md`, `docs/L2_development/cicd.md`

## CI 定義との整合性

CI 定義は `.github/workflows/` に3件存在する。shell tests 15本のうち CI job が直接実行するのは `tests/hooks/test-approval-hooks.sh` のみで、他14本と pytest（`tests/scripts/`）は CI job に含まれない。全 shell tests は ShellCheck の対象である。

根拠: `.github/workflows/deploy.yml:1-53`, `.github/workflows/shellcheck.yml:1-18`, `.github/workflows/test.yml:1-18`, `README.md:80-98`, `docs/L2_development/cicd.md`, `docs/L2_development/test.md`

## README / AGENTS / CLAUDE

- README は template が要求する Features、Installation、Usage、Design Principles を持つ。
- README の Features は28 command のうち内部委譲用を含む全 command を列挙する。
- repository root に license file は存在しないため、根拠のない license 名は README に記載しない。
- `AGENTS.md` は `CLAUDE.md`（project-local）への symlink であり、このリポジトリで作業する両 agent は project-local な AI 運用情報を参照する。
- 配布用ファイルは `global/CLAUDE.md` に分離されており、`~/.claude/CLAUDE.md` と `~/.codex/AGENTS.md` の両方がこれへ `install.sh` により自動 symlink される（issue #365 以前は `CLAUDE.md`（project-local）自身が配布物を兼ねていた。issue #367 で手動symlinkから自動化に変更）。
- `CLAUDE.md` の local tooling は観測済みの gh 2.97.0、Node.js v24.16.0、npm 11.13.0、mise hint と一致する。

根拠: `templates/readme.md:5-21`, `README.md`, `readlink AGENTS.md` の結果 `CLAUDE.md`, `CLAUDE.md:95-106`, `docs/.ai/repo.profile.json`（`deploy.claude_md`, `deploy.codex_agents_md`）, issue #365

## 未確認事項

- coverage collection / threshold は定義されていない。確認先: `tests/`、`.github/workflows/`。
- `tests/hooks/test-approval-hooks.sh` は CI（`test.yml`）で実行されるが、他13本の shell tests と pytest は引き続き CI で実行されない。確認先: `.github/workflows/test.yml`。
- Python / pytest の version pin と dependency manifest は存在しない。確認先: repository root の package・runtime 定義（現時点では未検出）。ローカル観測値は Python 3.12.3、pytest 9.1.1。

## 検出した不整合

`tests/commands/test-workflow-contracts.sh` は `commands/task.md` に `/rename` と installed helper 呼び出しが存在することを要求するが、commit `4f0953a` で task の同手順は削除されている。2026-08-21 の実行では該当2 assertion が失敗した。どちらを正とするかは実装変更の判断を伴うため `/init-docs` では修正せず、`tests/commands/test-workflow-contracts.sh:43-46` と `commands/task.md` を次の確認先とする。

## Done Criteria

| 条件 | 判定 | 理由 |
|---|---|---|
| docs の事実が実体と矛盾しない | yes | path、command、workflow、dependency、entry point を再観測した |
| Repo Profile と docs が相互に説明可能 | yes | 26 commands、28 command/skill、9 hooks を双方向に突合した |
| CI と docs が一致する | yes | Node.js 24 と site npm build/deploy を CI から採用した |
| 未確認事項が分離されている | yes | coverage、CI test 非登録、Python dependency pin 不在を明記した |
| repository-local contract tests が実装と一致する | no | workflow contract test の task `/rename` assertion が2件失敗した |

判定: 部分完了。生成・更新した docs、Repo Profile、CI の相互説明は成立するが、repository-local contract test と `commands/task.md` の不整合が残るため、リポジトリ全体の整合性は保証しない。
