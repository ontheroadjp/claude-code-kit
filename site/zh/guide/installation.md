# 安装

> **仅符号链接原则：** `~/.claude/` 和 `~/.codex/` 下的所有文件必须是指向本仓库的符号链接——不能是实际的文件副本。本仓库是唯一的事实来源；主目录下的路径只是参考点。

## 快速安装

最快的设置方式：

```bash
git clone https://github.com/ontheroadjp/core-toolkit-for-claude.git
cd core-toolkit-for-claude
./install.sh
```

这将创建以下符号链接：
- `commands/*.md` → `~/.claude/commands/` 和 `~/.codex/commands/`
- `hooks/*.sh` → `~/.claude/hooks/` 和 `~/.codex/hooks/`
- `skills/*/` → `~/.codex/skills/`
- `templates/*.md` → `~/.claude/templates/` 和 `~/.codex/templates/`

目标目录会自动创建。如果 `jq` 可用，安装器还会更新 `~/.claude/settings.json` 和 `~/.codex/hooks.json`。Codex 用户应先用 `/hooks` 检查并信任已注册的 hooks，再依赖它们。

## 手动设置

### Step 0：创建模板的符号链接（必须）

```bash
mkdir -p ~/.claude/templates ~/.codex/templates
for template in /path/to/core-toolkit-for-claude/templates/*.md; do
  ln -s "$template" ~/.claude/templates/
  ln -s "$template" ~/.codex/templates/
done
```

模板源文件保留在本仓库中。Claude Code 通过 `~/.claude/templates/` 下的符号链接引用它们，Codex CLI 则通过 `~/.codex/templates/` 下的符号链接引用。

### Step 1：创建命令的符号链接（全局——所有仓库）

```bash
ln -s /path/to/core-toolkit-for-claude/commands/work.md            ~/.claude/commands/work.md
ln -s /path/to/core-toolkit-for-claude/commands/triage-issues.md   ~/.claude/commands/triage-issues.md
ln -s /path/to/core-toolkit-for-claude/commands/task.md            ~/.claude/commands/task.md
ln -s /path/to/core-toolkit-for-claude/commands/patch.md           ~/.claude/commands/patch.md
ln -s /path/to/core-toolkit-for-claude/commands/docs-sync.md       ~/.claude/commands/docs-sync.md
ln -s /path/to/core-toolkit-for-claude/commands/init-docs.md       ~/.claude/commands/init-docs.md
ln -s /path/to/core-toolkit-for-claude/commands/review-resolve.md  ~/.claude/commands/review-resolve.md
ln -s /path/to/core-toolkit-for-claude/commands/codex-review.md    ~/.claude/commands/codex-review.md
ln -s /path/to/core-toolkit-for-claude/commands/new-issue.md       ~/.claude/commands/new-issue.md
```

如果手动安装到 Codex CLI，请在 `~/.codex/commands/` 下创建同样的链接。

这些命令现在可以作为 `/work`、`/triage-issues`、`/new-issue`、`/review-resolve`、`/codex-review`、`/task`、`/patch`、`/docs-sync` 和 `/init-docs` 使用。

### Step 2：创建 CLAUDE.md 的符号链接（全局——所有仓库）

```bash
ln -s /path/to/core-toolkit-for-claude/CLAUDE.md ~/.claude/CLAUDE.md
```

Claude Code 会在每个会话中自动加载 `~/.claude/CLAUDE.md`，因此 AI 操作指令会自动应用到所有仓库。如果某个仓库需要不同的指令，在其根目录放置一个本地 `CLAUDE.md`——本地优先于全局。

### Step 3：创建 hooks 的符号链接（可选）

```bash
mkdir -p ~/.claude/hooks
ln -s /path/to/core-toolkit-for-claude/hooks/auto-approve-readonly.sh \
      ~/.claude/hooks/auto-approve-readonly.sh
ln -s /path/to/core-toolkit-for-claude/hooks/guard-destructive-cmd.sh \
      ~/.claude/hooks/guard-destructive-cmd.sh
ln -s /path/to/core-toolkit-for-claude/hooks/log-token-usage.sh \
      ~/.claude/hooks/log-token-usage.sh
ln -s /path/to/core-toolkit-for-claude/hooks/log-access-prompt.sh \
      ~/.claude/hooks/log-access-prompt.sh
ln -s /path/to/core-toolkit-for-claude/hooks/log-access-tool.sh \
      ~/.claude/hooks/log-access-tool.sh
ln -s /path/to/core-toolkit-for-claude/hooks/log-access-stop.sh \
      ~/.claude/hooks/log-access-stop.sh
ln -s /path/to/core-toolkit-for-claude/hooks/cleanup-session.sh \
      ~/.claude/hooks/cleanup-session.sh
```

请参阅[配置](./configuration)了解如何在 `~/.claude/settings.json` 中注册 hooks。

对于 Codex CLI，请在 `~/.codex/hooks/` 下创建同样的 hook 符号链接，并在 `~/.codex/hooks.json` 中注册。如果 `jq` 可用，`./install.sh` 会自动完成。

### Step 4：创建 Codex skills 的符号链接（Codex CLI）

```bash
mkdir -p ~/.codex/skills
ln -s /path/to/core-toolkit-for-claude/skills/* ~/.codex/skills/
```

每个 skill 都是一个薄封装器，会读取对应的 `commands/*.md` 作为事实来源。

### Step 5：状态栏（可选）

在 Claude Code 状态栏中显示上下文使用率和速率限制：

```bash
./setup_statusline.sh
```

重启 Claude Code 以应用。

## 要求

- 已安装 [Claude Code](https://claude.ai/code)
- 使用 Codex skills 或 hooks 时需要安装 Codex CLI
- 已安装并认证 Git 和 gh CLI
- 已安装 jq
