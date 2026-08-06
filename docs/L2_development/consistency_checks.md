# Consistency Checks

最終実行: 2026-08-06

## docs → 実体

### Command / skill paths

- `commands/` には README を除いて23個の command specification が存在する。
- `skills/` には23個の `SKILL.md` が存在し、command basename と1:1で対応する。
- `docs/.ai/repo.profile.json` の `active_commands` と `skills` は、この23件を漏れなく列挙する。

根拠: `commands/` 実体一覧、`skills/` 実体一覧、`docs/.ai/repo.profile.json:active_commands`、`docs/.ai/repo.profile.json:skills`

### Hooks

`install.sh` が symlink 対象とする top-level hook script は9本で、Repo Profile の `hooks` と一致する。`hooks/lib/` の3 helper は top-level 配置対象ではない。

根拠: `install.sh:20-45`, `hooks/` 実体一覧、`docs/.ai/repo.profile.json:hooks`

### Runtime / build / test commands

Repo Profile の commands はすべて実体に対応する。

| 分類 | Repo Profile の command | 実体 |
|---|---|---|
| install | `./install.sh` | executable installer |
| statusline | `./setup_statusline.sh` | executable installer |
| site | `cd site && npm ci` | CI install step |
| site | `cd site && npm run docs:dev` | `site/package.json:scripts.docs:dev` |
| site | `cd site && npm run docs:build` | package script and CI build step |
| site | `cd site && npm run docs:preview` | `site/package.json:scripts.docs:preview` |
| analyze | `python3 scripts/analyze_access.py --all` | access log aggregator |
| analyze | `python3 scripts/analyze_auto_approve.py --all` | auto-approve log aggregator |
| analyze | `python3 scripts/analyze_token_usage.py --all` | token-usage log aggregator |
| shell test | `bash tests/hooks/test-approval-hooks.sh` | hook safety contract |
| shell test | `bash tests/commands/test-report-review.sh` | report-review contract |
| shell test | `bash tests/commands/test-coding-guidelines.sh` | coding guideline composition, routing, portability contract |
| shell test | `bash tests/install/test-install.sh` | installer contract |
| Python test | `python3 -m pytest tests/scripts/` | analysis-script contract |

根拠: `docs/.ai/repo.profile.json:commands`, `site/package.json:4-8`, `.github/workflows/deploy.yml:31-37`, `commands/analyze-access.md:27-35`, `commands/analyze-auto-approve.md:28-36`, `commands/analyze-token-usage.md:27-35`, `tests/` 実体一覧

## repo.profile.json ↔ docs

- `doc_roots` の4 directory は実在し、L0、L1、L2、L3 の生成済み構造と一致する。
- `primary_docs.investigation` と `primary_docs.structure` は実在する。
- `commands` の全13項目は `operation_model.md`、`test.md`、`cicd.md` のいずれかで説明される。
- `active_commands` 23件、`skills` 23件、`hooks` 9件は実体一覧と一致する。

根拠: `docs/.ai/repo.profile.json`, `docs/L2_development/operation_model.md`, `docs/L2_development/test.md`, `docs/L2_development/cicd.md`

## CI 定義との整合性

CI 定義は `.github/workflows/` に3件存在する: `deploy.yml`（Node.js 24、npm cache、`site/package-lock.json`、`site/` での `npm ci` と `npm run docs:build`、`site/.vitepress/dist` upload、GitHub Pages deploy）、`shellcheck.yml`（全 `*.sh` への `shellcheck -x`）、`test.yml`（`tests/hooks/test-approval-hooks.sh` を実行する `approval-hooks` job）。この3件を docs と README に反映した。`tests/commands/test-report-review.sh`・`tests/commands/test-coding-guidelines.sh`・`tests/install/test-install.sh`・pytest（`tests/scripts/`）は依然として CI job に含まれない。

根拠: `.github/workflows/deploy.yml:1-53`, `.github/workflows/shellcheck.yml:1-18`, `.github/workflows/test.yml:1-18`, `README.md:80-98`, `docs/L2_development/cicd.md`, `docs/L2_development/test.md`

## README / AGENTS / CLAUDE

- README は template が要求する Features、Installation、Usage、Design Principles を持つ。
- README の Features は23 command のうち内部委譲用を含む全 command を列挙する。
- repository root に license file は存在しないため、根拠のない license 名は README に記載しない。
- `AGENTS.md` は `CLAUDE.md` への symlink であり、両 agent は同じ AI 運用情報を参照する。
- `CLAUDE.md` の local tooling は 2026-08-06 の観測値（gh 2.96.0、Node.js v24.16.0、npm 11.13.0、mise hint）と一致する。

根拠: `templates/readme.md:5-21`, `README.md`, `readlink AGENTS.md` の結果 `CLAUDE.md`, `CLAUDE.md:95-106`

## 未確認事項

- coverage collection / threshold は定義されていない。確認先: `tests/`、`.github/workflows/`。
- `tests/hooks/test-approval-hooks.sh` は CI（`test.yml`）で実行されるが、`tests/commands/test-report-review.sh`・`tests/commands/test-coding-guidelines.sh`・`tests/install/test-install.sh`・pytest は引き続き CI で実行されない。確認先: `.github/workflows/test.yml`。
- Python / pytest の version pin と dependency manifest は存在しない。確認先: repository root の package・runtime 定義（現時点では未検出）。ローカル観測値は Python 3.12.3、pytest 9.1.1。

## Done Criteria

| 条件 | 判定 | 理由 |
|---|---|---|
| docs の事実が実体と矛盾しない | yes | path、command、workflow、dependency、entry point を再観測した |
| Repo Profile と docs が相互に説明可能 | yes | 14 commands、23 command/skill、9 hooks を双方向に突合した |
| CI と docs が一致する | yes | Node.js 24 と site npm build/deploy を CI から採用した |
| 未確認事項が分離されている | yes | coverage、CI test 非登録、Python dependency pin 不在を明記した |

判定: 完了。
