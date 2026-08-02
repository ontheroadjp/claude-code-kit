# CLAUDE.md specification

## 目的・役割

`CLAUDE.md` はこの repository で作業する AI agent の運用起点であり、`AGENTS.md` からも symlink 参照される single source of truth である。

根拠: `CLAUDE.md:1-15`

## 動作の概要

- command routing と repository 操作ルールを定義する
- symlink-only 原則と docs/task workflow の境界を示す
- local tooling と template installed path を記録する

根拠: `CLAUDE.md:13-97`

## 主要な判定ロジック・フロー

template の実体は repository の `templates/` に保持する。Claude Code は `~/.claude/templates/*.md`、Codex CLI は `~/.codex/templates/*.md` の symlink 経由で同じ実体を参照する。

根拠: `CLAUDE.md:32-47`

## 重要な設計判断

`~/.claude/` と `~/.codex/` を symlink-only とすることで、agent ごとの installed path を提供しながら repository を唯一の編集対象として維持する。

## 統合ポイント

- `AGENTS.md` → `CLAUDE.md` symlink
- installer: `install.sh`
- template source: `templates/*.md`

## 注意事項・既知の制限

- home directory 配下の symlink target を直接編集しない
- repository 変更は `/work` workflow を経由する
