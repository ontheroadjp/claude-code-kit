# Repository Structure

## 観測した構造

```text
core-toolkit-for-claude/
├── AGENTS.md                    # CLAUDE.md（project-local）への symlink（Codex CLI 向け入口）
├── CLAUDE.md                    # このリポジトリ自身の project-local な AI 運用指示（配布物ではない）
├── global/CLAUDE.md             # 配布用フレームワークファイル。~/.claude/CLAUDE.md・~/.codex/AGENTS.md の symlink 元（issue #365）
├── README.md                    # 人間向け概要、インストール、利用手順
├── install.sh                   # symlink、hook settings、Codex status line 登録
├── .github/workflows/deploy.yml     # VitePress site を GitHub Pages へ deploy
├── .github/workflows/shellcheck.yml # 全 *.sh に ShellCheck を実行
├── commands/                    # Claude/Codex が読む Markdown command 仕様（README.md あり）
├── docs/                        # /init-docs が管理する L0-L3 設計 docs
├── hooks/                       # Claude Code / Codex hook scripts（README.md あり）
├── logs/                        # access / auto-approval / token usage の月次ログ
├── scripts/                     # status line setup / token usage 表示、ログ解析 scripts（README.md あり）
├── site/                        # VitePress documentation site
├── skills/                      # Codex skill wrappers（README.md あり）
├── tests/                       # hook などの検証 scripts（README.md あり）
└── templates/                   # issue / PR / README templates（README.md あり）
```

根拠: `rg --files -uu`, `.github/workflows/deploy.yml:1-53`, `.github/workflows/shellcheck.yml:1-19`, `site/package.json:1-14`, `README.md`（Repository Structure）, issue #365

## ディレクトリ責務

### `commands/`

Claude Code / Codex CLI が読む Markdown command 仕様を置く。`work.md` が通常実装入口で、`git-pr.md` のready PR作成で `/work` と `/task` は完結する。review後の単一PR deliveryは `git-pr-merge.md` がapproved head・owned worktree・current-head validation・squash mergeを管理する。`task-manager.md` は複数source PRを準備し、complete Draft set承認後に同delivery workflowへ入力順で委譲する。

根拠: `commands/work.md:1-187`, `commands/git-pr.md:62-65`, `commands/git-pr-merge.md:1-147`, `commands/task-manager.md:1-412`, `commands/README.md`

### `skills/`

Codex 用 skill wrapper を置く。各 `SKILL.md` は対応する command markdown を Source of Truth として読むことを指示する。

根拠: `skills/init-docs/SKILL.md:1-14`, `skills/work/SKILL.md`, `skills/README.md`

### `hooks/`

Claude Code / Codex hook scripts と共有 helper を置く。現在存在する hook は `auto-approve-readonly.sh`, `cleanup-session.sh`, `guard-destructive-cmd.sh`, `log-access-prompt.sh`, `log-access-stop.sh`, `log-access-tool.sh`, `log-token-usage.sh`, `notify-slack.sh`, `tmux-agent-status.sh` の 9 本である。`hooks/lib/approval-safety.sh` は PreToolUse Bash safety checks を共有する helper である。

根拠: `hooks/` 実体一覧, `hooks/lib/approval-safety.sh`, `install.sh:29-41`, `hooks/README.md`

### `tests/`

shell 検証 scripts と Python の pytest suite を置く。command testsにはagenda/coding/workflow/worktree契約に加え、`test-task-manager.sh`のbatch orchestration契約と`test-git-pr-merge.sh`のreviewed PR delivery契約がある。installer、hook safety、worktree linker、analysis scriptsのtestsも配置する。

根拠: `tests/README.md:1-88`, `tests/commands/test-task-manager.sh:1-132`, `tests/commands/test-git-pr-merge.sh:1-81`, `tests/hooks/test-approval-hooks.sh`, `tests/install/test-install.sh`, `tests/scripts/`

### `templates/`

issue、PR、README scaffold の template 実体を置く。`install.sh` は各ファイルを Claude Code 用の `~/.claude/templates/` と Codex CLI 用の `~/.codex/templates/` の両方へ symlink し、commands は実行 agent に応じた installed path を参照する。

根拠: `templates/issue.md:1-25`, `templates/pr.md:1-32`, `commands/task.md:11-18`, `commands/new-issue.md:11-18`, `install.sh:10-19`, `install.sh:56-63`, `templates/README.md`

### `docs/`

`/init-docs` が生成・更新する L0-L3 設計 docs と `docs/.ai/repo.profile.json` を置く。`primary_docs` は調査入口として `docs/L3_implementation/specification_summary.md` と `docs/L1_project/repository_structure.md` を指す。`docs/L0_concept/`（concept.md, policy.md）は `/init-docs` が存在しない場合のみ新規作成し、以後は `/concept-maker` によるユーザー承認付き追記でのみ更新される。`docs/.ai/l0_candidates.md` は `/docs-sync` が積む L0 昇格候補のキューで、候補がある場合のみ存在する（`/concept-maker` が消化するたびに減り、空になると削除される）。

根拠: `commands/init-docs.md:75-219`, `docs/.ai/repo.profile.json`, `commands/docs-sync.md`, `commands/concept-maker.md`

### `site/`

VitePress の公開サイトを置く。`site/package.json` に npm scripts と依存関係、`site/.vitepress/config.mts` に `locales` 設定（en / ja / zh）と navigation/sidebar/site metadata が定義される。コンテンツは `site/`（英語）・`site/ja/`（日本語）・`site/zh/`（中国語簡体字）に配置される。GitHub Actions は `site/` で `npm ci` と `npm run docs:build` を実行する。

根拠: `site/package.json:1-14`, `site/.vitepress/config.mts:1-183`, `.github/workflows/deploy.yml:24-42`

### `scripts/` と status line setup

`scripts/setup_statusline_for_claude.sh` は `scripts/statusline.sh` を `~/.claude/statusline.sh` に symlink し、`~/.claude/settings.json` に `statusLine` を追加する。`scripts/setup_statusline_for_codex.sh` は `~/.codex/config.toml` の `[tui].status_line` を4項目へ冪等更新し、`install.sh` からも呼ばれる。`scripts/statusline.sh` は `jq` と `bc` を使って Claude Code の context / rate limit 情報を表示する。ログ解析 scripts は `logs/<type>/*.log` を集計し JSON を標準出力へ出力する。

根拠: `scripts/setup_statusline_for_claude.sh:6-57`, `scripts/setup_statusline_for_codex.sh:6-93`, `install.sh:108-109`, `scripts/statusline.sh:10-83`

### `logs/`

access、auto-approval、token usage の月次ログを置く。log hooks と token usage script が repository-local な観測記録として利用する。

根拠: `logs/` 実体一覧、`hooks/log-access-stop.sh`、`hooks/log-token-usage.sh`

## デプロイ構成

| 対象 | source | target | 方法 | 根拠 |
|---|---|---|---|---|
| Claude commands | `commands/*.md` | `~/.claude/commands/*.md` | `install.sh` が symlink | `install.sh:21-26` |
| Codex commands | `commands/*.md` | `~/.codex/commands/*.md` | `install.sh` が symlink | `install.sh:28-33` |
| Claude hooks | `hooks/*.sh` | `~/.claude/hooks/*.sh` | `install.sh` が symlink | `install.sh:35-40` |
| Codex hooks | `hooks/*.sh` | `~/.codex/hooks/*.sh`, `~/.codex/hooks.json` | `install.sh` が symlink と hooks.json 登録 | `install.sh:42-47`, `install.sh:72-194` |
| Codex skills | `skills/*/` | `~/.codex/skills/*` | `install.sh` が symlink | `install.sh:49-54` |
| Claude templates | `templates/*.md` | `~/.claude/templates/*.md` | `install.sh` が個別 symlink | `install.sh:10-19`, `install.sh:56-63` |
| Codex templates | `templates/*.md` | `~/.codex/templates/*.md` | `install.sh` が個別 symlink | `install.sh:10-19`, `install.sh:56-63` |
| Claude statusline | `scripts/statusline.sh` | `~/.claude/statusline.sh` | `scripts/setup_statusline_for_claude.sh` が symlink | `scripts/setup_statusline_for_claude.sh:6-28` |
| Codex statusline | `scripts/setup_statusline_for_codex.sh` | `~/.codex/config.toml` | `install.sh` が専用 installer を実行 | `install.sh:108-109`, `scripts/setup_statusline_for_codex.sh:6-93` |
| site | `site/.vitepress/dist` | GitHub Pages | GitHub Actions | `.github/workflows/deploy.yml:39-52` |
| Claude global instructions | `global/CLAUDE.md` | `~/.claude/CLAUDE.md` | `install.sh` が symlink | `install.sh`, `docs/.ai/repo.profile.json`（`deploy.claude_md`）, issue #365, issue #367 |
| Codex global instructions | `global/CLAUDE.md` | `~/.codex/AGENTS.md` | `install.sh` が symlink | `install.sh`, `docs/.ai/repo.profile.json`（`deploy.codex_agents_md`）, issue #365, issue #367 |

## 補足

`site/.vitepress/dist/` は `.gitignore` 対象の build output であり、source of truth ではない。根拠: `.gitignore:12-15`, `.github/workflows/deploy.yml:39-42`
