# Consistency Checks

最終実行: 2026-08-02

## docs → 実体

### Command / skill paths

- `commands/` には README を除いて17個の command specification が存在する。
- `skills/` には17個の `SKILL.md` が存在し、`report-review` と `pr-review` を含め command と1:1で対応する。
- `/work` が参照する `commands/report-review.md`、`commands/task.md`、`commands/patch.md` はすべて存在する。

根拠: `rg --files commands -g '*.md'`、`rg --files skills -g 'SKILL.md'`、`commands/work.md:53-115`

### Hooks

`install.sh` が `hooks/*.sh` として symlink する top-level script は9本である。Notification / Stop の Slack 通知を含む event registration は存在する。`hooks/lib/approval-safety.sh` は top-level symlink 対象ではなく、approval hooks が source する共有 helper である。

根拠: `install.sh:33-45`, `install.sh:158-187`, `hooks/` 実体一覧、`hooks/lib/approval-safety.sh`

### Tests

次の4 command は実ファイルに対応し、Bash で実行可能である。

| command | target |
|---|---|
| `bash tests/hooks/test-approval-hooks.sh` | hook safety contract |
| `bash tests/commands/test-pr-review.sh` | pr-review declarative contract |
| `bash tests/commands/test-report-review.sh` | report-review declarative contract |
| `bash tests/install/test-install.sh` | Claude/Codex template symlink と installer idempotency contract |

根拠: `tests/` 実体一覧、`docs/.ai/repo.profile.json:commands`

### Runtime / build commands

| command | 実体 |
|---|---|
| `./install.sh` | executable installer |
| `./setup_statusline.sh` | executable statusline installer |
| `cd site && npm ci` | CI install step |
| `cd site && npm run docs:dev` | `site/package.json:scripts.docs:dev` |
| `cd site && npm run docs:build` | package script and CI build step |
| `cd site && npm run docs:preview` | `site/package.json:scripts.docs:preview` |

根拠: `install.sh`, `setup_statusline.sh`, `site/package.json:4-8`, `.github/workflows/deploy.yml:17-42`

## repo.profile.json ↔ docs

- `doc_roots` の4 directory は実在する。
- `primary_docs.investigation` と `primary_docs.structure` は実在する。
- `active_commands` は command specifications 17件と一致する。
- `skills` は skill wrappers 17件と一致する。
- `hooks` は installer が配置する top-level hook scripts 9件と一致する。
- `commands` の install / site / 4 test commands は `operation_model.md`、`test.md`、`cicd.md` で説明される。

根拠: `docs/.ai/repo.profile.json`、`docs/L2_development/operation_model.md`、`docs/L2_development/test.md`、`docs/L2_development/cicd.md`

## CI 定義との整合性

CI の事実は `.github/workflows/deploy.yml` を優先した。Node.js 24、npm cache、`site/package-lock.json`、`site/` での `npm ci` と `npm run docs:build`、`site/.vitepress/dist` upload、GitHub Pages deploy を docs に反映している。shell tests は CI job に含まれないことを明示した。

根拠: `.github/workflows/deploy.yml:17-53`, `docs/L2_development/cicd.md`, `docs/L2_development/test.md`

## AGENTS / CLAUDE

`AGENTS.md` は `CLAUDE.md` への symlink である。Claude Code と Codex CLI は同じ AI 運用情報を参照する。

根拠: `readlink AGENTS.md` の結果 `CLAUDE.md`

## 未確認事項

- shell tests の coverage collection / threshold は定義されていない。確認先: `tests/`、`.github/workflows/`。
- shell tests は CI で実行されない。確認先: `.github/workflows/deploy.yml`。
- npm audit findings の解消 version は一部未提供である。確認先: `site/package-lock.json` と再実行時の `npm audit --json`。
- `install.sh` が生成する `skills/pr-review/pr-review` と `skills/report-review/report-review` の self-referential symlink は `.gitignore` に個別 entry がない。installer 実行後の working tree 影響は `.gitignore` と `install.sh:61-66` を確認する。

## Done Criteria

| 条件 | 判定 | 理由 |
|---|---|---|
| docs の事実が実体と矛盾しない | yes | path、command、workflow、dependency を再観測した |
| repo profile と docs が相互に説明可能 | yes | command/skill/hook/4 test lists と説明先を突合した |
| CI と docs が一致する | yes | Node.js 24 と site npm build/deploy を CI から採用した |
| 未確認事項が分離されている | yes | coverage と CI test 非登録を明記した |

判定: 完了。
