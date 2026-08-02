# /new-issue specification

## 目的・役割

`commands/new-issue.md` は rough idea を実装可能な GitHub issue に整形する任意の pre-`/work` workflow である。実装や branch 操作は行わない。

根拠: `commands/new-issue.md:1-9`

## 動作の概要

ユーザーから背景・制約・完了条件を取得し、scope 分割をユーザーが決定した後、issue template に沿った英語 draft を確認して GitHub issue を作成する。

根拠: `commands/new-issue.md:17-123`

## 主要な判定ロジック

template root は実行 agent ごとに切り替える。Claude Code は `~/.claude/templates`、Codex CLI は `~/.codex/templates` を `TEMPLATES_DIR` とし、`${TEMPLATES_DIR}/issue.md` を利用する。

根拠: `commands/new-issue.md:7-13`, `commands/new-issue.md:64-71`

## 重要な設計判断

template の source of truth は repository に保持し、agent 固有の installed path から symlink 経由で読む。これにより command 自体は両 agent で共有しつつ、各 runtime の設定 root に閉じた参照を使える。

## 統合ポイント

- optional predecessor: `/work`
- template: `${TEMPLATES_DIR}/issue.md`
- GitHub: `gh label list`, `gh issue create`

## 注意事項・既知の制限

- scope 分割はユーザー決定が必須
- issue title/body は英語
- `/work` を自動実行しない
