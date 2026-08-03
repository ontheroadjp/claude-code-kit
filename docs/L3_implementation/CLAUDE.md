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

`/pr-review` が起動する reviewer subprocess の実行先は `/pr-review-exec` であると明記している。reviewer subprocess はこの repository 内で実行されるため `CLAUDE.md` を project instructions として自動的に読むが、ルーティング表に `pr-review-exec.md` を `review-resolve.md`・`pr-review.md` と並ぶ自己完結フローとして明記することで、reviewer が `/pr-review` へ誤って迷い込むことを防ぐ。

根拠: `CLAUDE.md:15-18`

## 重要な設計判断

`~/.claude/` と `~/.codex/` を symlink-only とすることで、agent ごとの installed path を提供しながら repository を唯一の編集対象として維持する。

## 統合ポイント

- `AGENTS.md` → `CLAUDE.md` symlink
- installer: `install.sh`
- template source: `templates/*.md`

## 注意事項・既知の制限

- home directory 配下の symlink target を直接編集しない
- repository 変更は `/work` workflow を経由する

## 変更履歴（git log より自動生成）

- 14b4255 refactor(#203): decouple pr-review reviewer execution into pr-review-exec
- 27f1861 feat(#76): install templates for claude and codex
- 5faaf5d docs: initialize project documentation (init-docs)
- 145876c fix(#185): align pr-review with repository workflow rules
- 4e96f9c feat(#142): add session-scoped temp hook access
- 2dc74bd docs: initialize project documentation (init-docs)
- 07ae6ac docs: initialize project documentation (init-docs)
- bc2900f feat(#63): add /new-issue skill for idea-to-issue workflow
- 4e87fe4 feat(#56): make /review-resolve self-contained, add opinion presentation
- d14f403 docs(CLAUDE.md): add npm lazy-load instruction
