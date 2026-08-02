# /init-docs specification

## 目的・役割

`commands/init-docs.md` は repository の実体を再観測し、L0-L3 docs、repo profile、README、AI guidance を再構築する重い初期化 workflow である。

根拠: `commands/init-docs.md:1-35`

## 動作の概要

専用 branch 上で repository/tooling を観測し、docs と README の整合性を検証した後、ユーザー承認を得て commit と PR を作成する。

根拠: `commands/init-docs.md:21-47`, `commands/init-docs.md:350-420`

## 主要な判定ロジック

README scaffold の基準は `${TEMPLATES_DIR}/readme.md` である。`TEMPLATES_DIR` は Claude Code では `~/.claude/templates`、Codex CLI では `~/.codex/templates` とする。

根拠: `commands/init-docs.md:3-5`, `commands/init-docs.md:272-289`

## 重要な設計判断

template 実体を repository に保持し、agent 固有 installed path の symlink から参照することで、同じ scaffold を Claude/Codex の双方で利用する。

## 統合ポイント

- entry from `/docs-sync` HARD STOP or explicit user invocation
- README template: `${TEMPLATES_DIR}/readme.md`
- output: `docs/.ai/repo.profile.json`, L0-L3 docs, README, CLAUDE.md/AGENTS.md

## 注意事項・既知の制限

- 通常の局所 docs 更新には使用しない
- commit/PR 前にユーザー確認が必須
