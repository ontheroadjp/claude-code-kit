# インストール

> **symlink-only 原則:** `~/.claude/` と `~/.codex/` 配下に置くファイルは全てこのリポジトリへのシンボリックリンクとし、実体ファイルは置かないこと。このリポジトリが single source of truth。ホームディレクトリ側のパスは参照ポイントに過ぎない。

## クイックインストール

最も簡単なセットアップ方法:

```bash
git clone https://github.com/ontheroadjp/core-toolkit-for-claude.git
cd core-toolkit-for-claude
./install.sh
```

以下のシンボリックリンクが作成されます:
- `commands/*.md` → `~/.claude/commands/` および `~/.codex/commands/`
- `hooks/*.sh` → `~/.claude/hooks/` および `~/.codex/hooks/`
- `skills/*/` → `~/.codex/skills/`
- `templates/*.md` → `~/.claude/templates/` および `~/.codex/templates/`

対象ディレクトリは自動で作成されます。`jq` が利用可能な場合、`~/.claude/settings.json` と `~/.codex/hooks.json` も更新されます。Codex ユーザーは `/hooks` で登録済み hooks を確認し、trust してから利用してください。

## 手動セットアップ

### Step 0: テンプレートのシンボリックリンク作成（必須）

```bash
mkdir -p ~/.claude/templates ~/.codex/templates
for template in /path/to/core-toolkit-for-claude/templates/*.md; do
  ln -s "$template" ~/.claude/templates/
  ln -s "$template" ~/.codex/templates/
done
```

テンプレートの実体はこのリポジトリに保持します。Claude Code は `~/.claude/templates/`、Codex CLI は `~/.codex/templates/` 配下のシンボリックリンクから参照します。

### Step 1: コマンドのシンボリックリンク作成（グローバル — 全リポジトリ）

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

Codex CLI へ手動インストールする場合は、同じリンクを `~/.codex/commands/` 配下にも作成します。

これで `/work`、`/triage-issues`、`/new-issue`、`/review-resolve`、`/codex-review`、`/task`、`/patch`、`/docs-sync`、`/init-docs` が利用できるようになります。

### Step 2: CLAUDE.md のシンボリックリンク作成（グローバル — 全リポジトリ）

```bash
ln -s /path/to/core-toolkit-for-claude/CLAUDE.md ~/.claude/CLAUDE.md
```

Claude Code は全セッションで `~/.claude/CLAUDE.md` を自動読み込みするため、AI 運用指示が全リポジトリに適用されます。リポジトリ固有の指示が必要な場合はルートに `CLAUDE.md` を置いてください（ローカルがグローバルより優先されます）。

### Step 3: hooks のシンボリックリンク作成（任意）

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

`~/.claude/settings.json` への hooks 登録は[設定](./configuration)を参照してください。

Codex CLI では同じ hook symlink を `~/.codex/hooks/` 配下に作成し、`~/.codex/hooks.json` に登録します。`jq` が利用可能なら `./install.sh` が自動で実行します。

### Step 4: Codex skills のシンボリックリンク作成（Codex CLI）

```bash
mkdir -p ~/.codex/skills
ln -s /path/to/core-toolkit-for-claude/skills/* ~/.codex/skills/
```

各 skill は、対応する `commands/*.md` を source of truth として読む薄いラッパーです。

### Step 5: ステータスライン（任意）

Claude Code のステータスバーにコンテキスト使用率とレート制限を表示します:

```bash
./setup_statusline.sh
```

Claude Code を再起動すると反映されます。

## 要件

- [Claude Code](https://claude.ai/code) のインストール
- Codex skill または hook を使う場合は Codex CLI のインストール
- Git と gh CLI のインストールおよび認証済みであること
- jq のインストール
