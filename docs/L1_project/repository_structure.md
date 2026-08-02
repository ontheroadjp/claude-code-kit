# Repository Structure

## 観測した構造

```text
core-toolkit-for-claude/
├── AGENTS.md                    # CLAUDE.md への symlink（Codex CLI 向け入口）
├── CLAUDE.md                    # AI 運用指示の source of truth
├── README.md                    # 人間向け概要、インストール、利用手順
├── install.sh                   # commands/hooks/skills/templates symlink と Claude/Codex hook settings 登録
├── setup_statusline.sh          # status line symlink と settings 登録
├── .github/workflows/deploy.yml # VitePress site を GitHub Pages へ deploy
├── commands/                    # Claude/Codex が読む Markdown command 仕様（README.md あり）
├── docs/                        # /init-docs が管理する L0-L3 設計 docs
├── hooks/                       # Claude Code / Codex hook scripts（README.md あり）
├── logs/                        # access / auto-approval / token usage の月次ログ
├── scripts/                     # status line / token usage 表示 scripts（README.md あり）
├── site/                        # VitePress documentation site
├── skills/                      # Codex skill wrappers（README.md あり）
├── tests/                       # hook などの検証 scripts（README.md あり）
└── templates/                   # issue / PR / README templates（README.md あり）
```

根拠: `rg --files -uu`, `.github/workflows/deploy.yml:1-53`, `site/package.json:1-14`

## ディレクトリ責務

### `commands/`

Claude Code / Codex CLI が読む Markdown command 仕様を置く。`work.md` が通常入口で、report issue は `report-review.md`、実装は `task.md` または `patch.md` に委譲する。PR 作成後は `git-pr.md` が `pr-review.md` へ引き継ぐ。

根拠: `commands/work.md:1-115`, `commands/report-review.md:1-14`, `commands/git-pr.md:63-73`, `commands/README.md`

### `skills/`

Codex 用 skill wrapper を置く。各 `SKILL.md` は対応する command markdown を Source of Truth として読むことを指示する。

根拠: `skills/init-docs/SKILL.md:1-14`, `skills/work/SKILL.md`, `skills/README.md`

### `hooks/`

Claude Code / Codex hook scripts と共有 helper を置く。現在存在する hook は `auto-approve-readonly.sh`, `cleanup-session.sh`, `guard-destructive-cmd.sh`, `log-access-prompt.sh`, `log-access-stop.sh`, `log-access-tool.sh`, `log-token-usage.sh`, `notify-slack.sh`, `tmux-agent-status.sh` の 9 本である。`hooks/lib/approval-safety.sh` は PreToolUse Bash safety checks を共有する helper である。

根拠: `hooks/` 実体一覧, `hooks/lib/approval-safety.sh`, `install.sh:29-41`, `hooks/README.md`

### `tests/`

shell 検証 scripts を置く。`tests/hooks/test-approval-hooks.sh` は hook safety、`tests/commands/test-pr-review.sh` と `test-report-review.sh` は Markdown workflow の必須句・禁止操作、`tests/install/test-install.sh` は fixture HOME に対する template symlink と installer の冪等性を検証する。

根拠: `tests/hooks/test-approval-hooks.sh`, `tests/commands/test-pr-review.sh`, `tests/commands/test-report-review.sh`, `tests/install/test-install.sh:1-71`

### `templates/`

issue、PR、README scaffold の template 実体を置く。`install.sh` は各ファイルを Claude Code 用の `~/.claude/templates/` と Codex CLI 用の `~/.codex/templates/` の両方へ symlink し、commands は実行 agent に応じた installed path を参照する。

根拠: `templates/issue.md:1-25`, `templates/pr.md:1-32`, `commands/task.md:11-18`, `commands/new-issue.md:11-18`, `install.sh:10-19`, `install.sh:56-63`, `templates/README.md`

### `docs/`

`/init-docs` が生成・更新する L0-L3 設計 docs と `docs/.ai/repo.profile.json` を置く。`primary_docs` は調査入口として `docs/L3_implementation/specification_summary.md` と `docs/L1_project/repository_structure.md` を指す。

根拠: `commands/init-docs.md:75-219`, `docs/.ai/repo.profile.json`

### `site/`

VitePress の公開サイトを置く。`site/package.json` に npm scripts と依存関係、`site/.vitepress/config.mts` に `locales` 設定（en / ja / zh）と navigation/sidebar/site metadata が定義される。コンテンツは `site/`（英語）・`site/ja/`（日本語）・`site/zh/`（中国語簡体字）に配置される。GitHub Actions は `site/` で `npm ci` と `npm run docs:build` を実行する。

根拠: `site/package.json:1-14`, `site/.vitepress/config.mts:1-183`, `.github/workflows/deploy.yml:24-42`

### `scripts/` と `setup_statusline.sh`

`setup_statusline.sh` は `scripts/statusline.sh` を `~/.claude/statusline.sh` に symlink し、`~/.claude/settings.json` に `statusLine` を追加する。`scripts/statusline.sh` は `jq` と `bc` を使って context / rate limit 情報を表示する。

根拠: `setup_statusline.sh:6-55`, `scripts/statusline.sh:10-83`, `scripts/README.md`

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
| statusline | `scripts/statusline.sh` | `~/.claude/statusline.sh` | `setup_statusline.sh` が symlink | `setup_statusline.sh:6-28` |
| site | `site/.vitepress/dist` | GitHub Pages | GitHub Actions | `.github/workflows/deploy.yml:39-52` |

## 補足

`site/.vitepress/dist/` は `.gitignore` 対象の build output であり、source of truth ではない。根拠: `.gitignore:12-15`, `.github/workflows/deploy.yml:39-42`
