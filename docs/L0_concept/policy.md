# Policy

## 技術選定ポリシー

- コマンド仕様は Markdown で管理する。AI が `commands/*.md` を読んで実行するため、別 DSL は置かない。根拠: `commands/work.md:1-4`, `commands/task.md:1-9`
- Codex skill は `skills/*/SKILL.md` に置き、対応する `commands/*.md` を Source of Truth として読む薄いラッパーにする。根拠: `skills/init-docs/SKILL.md:1-14`
- Claude Code hooks と補助ツールは Bash で実装する。根拠: `hooks/*.sh`, `scripts/*.sh`, `install.sh:1-3`
- 公開サイトは `site/` 配下の VitePress と npm で管理する。根拠: `site/package.json:1-14`, `.github/workflows/deploy.yml:24-37`

## セキュリティ方針

- 破壊的 Bash 操作は `hooks/lib/approval-safety.sh` の共有判定を `auto-approve-readonly.sh` と `guard-destructive-cmd.sh` から利用して block する。根拠: `hooks/lib/approval-safety.sh:1-87`, `hooks/guard-destructive-cmd.sh:1-25`
- 読み取り専用操作とセッション承認済み操作を `hooks/auto-approve-readonly.sh` が自動承認し、repo 内 write には WIP commit による動的防御を適用する。根拠: `hooks/auto-approve-readonly.sh:375-590`
- セッション承認は Stop hook で削除し、次セッションへ持ち越さない。根拠: `hooks/cleanup-session.sh:39-50`
- コミット前に個人情報、IP アドレス、ドメイン名、絶対パスを staged diff から確認する。根拠: `commands/git-commit.md:47-61`
- `/report-review` はファイル、Git state、GitHub issue / PR を変更せず、評価を標準出力だけに提示する。根拠: `commands/report-review.md:5-14`, `commands/report-review.md:63-91`

## 運用・性能方針

- hooks は Claude Code の通常操作を過度に妨げない。ログ書き込み失敗時も処理を継続する実装がある。根拠: `hooks/auto-approve-readonly.sh:15-22`, `hooks/log-access-stop.sh`, `hooks/log-token-usage.sh`
- VitePress サイトは CI で `site/` を working directory として `npm ci` と `npm run docs:build` を実行し、GitHub Pages へデプロイする。根拠: `.github/workflows/deploy.yml:31-52`
- `scripts/statusline.sh` は `jq` と `bc` を使って context 使用率を表示する。根拠: `scripts/statusline.sh:10-31`

## 禁止事項

| 禁止事項 | 理由 | 根拠 |
|---|---|---|
| `~/.claude/` または `~/.codex/` へ実体ファイルを置く | symlink-only 原則と single source of truth を壊す | `README.md:26-45`, `CLAUDE.md:34-47` |
| `/task` で一般 docs を直接更新する | 一般 docs 同期は `/docs-sync` の責務。L3 per-file doc のみ task が管理する | `commands/task.md:5-9`, `commands/task.md:113-137` |
| `/report-review` で実装・永続化・GitHub 投稿を行う | report issue は評価であり変更要求ではない | `commands/report-review.md:5-14` |
| `/docs-sync` で L0 を通常更新する | L0 は意思決定記録であり git diff 追従対象ではない | `commands/docs-sync.md:86-88` |
| `git add -A` / `git add .` を使う | 意図しないファイルをコミットしやすい | `commands/init-docs.md:374-376` |
| AI が `git push --force` など不可逆な git 操作を自動実行する | 共有履歴・未追跡変更を破壊する可能性がある | `CLAUDE.md:55-61`, `hooks/guard-destructive-cmd.sh:90-126` |

## 整合性方針

`install.sh` が settings に登録する hook は、現在の `hooks/` 配下に存在する script のみとする。存在しない hook を設定に登録しない。

根拠: `install.sh:80-87`, `hooks/` 実体一覧
