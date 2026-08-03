# Concept

## 目的

このリポジトリは、Claude Code と Codex CLI の AI 駆動開発ワークフローを、Markdown のコマンド仕様、Codex skill ラッパー、Claude Code hooks、共通テンプレート、VitePress サイトとして一元管理する。

根拠: `README.md:1-3`, `commands/work.md:1-4`, `skills/init-docs/SKILL.md:1-14`, `site/package.json:1-14`

## 解決する問題

曖昧な AI 作業開始による、ドキュメント更新漏れ、issue/PR 追跡漏れ、評価目的の report issue の誤実装、レビューコメント対応の属人化、破壊的 git 操作、セッション承認の持ち越しを抑制する。

このため、`/work` は report label を実装 routing より先に判定し、report issue を read-only `/report-review` へ委譲する。それ以外では現状調査と docs 変更要否による routing を担い、`/task` は issue と PR を伴う実装（ゴールは ready PR の作成まで）、`/patch` は軽微修正、`/docs-sync` は git diff に基づく docs 同期、`/review-resolve` は PR レビューコメント対応を分離する。

根拠: `commands/work.md:47-115`, `commands/report-review.md:1-91`, `commands/task.md:30-170`, `commands/patch.md:11-95`, `commands/docs-sync.md:39-173`, `commands/review-resolve.md:1-6`

## 対象ユーザー

Claude Code または Codex CLI を使い、実装・ドキュメント同期・PR 作成・レビュー対応を再現可能な手順で進めたい開発者を対象とする。

根拠: `README.md:5-15`, `README.md:63-85`, `skills/*/SKILL.md`

## 設計上の制約

- `~/.claude/` と `~/.codex/` 配下は symlink-only とし、このリポジトリを single source of truth とする。template の実体は `templates/` に保持し、各 agent の `templates/` 配下から symlink で参照する。根拠: `README.md:26-45`, `CLAUDE.md:34-47`, `install.sh:10-19`, `install.sh:56-63`
- 通常作業は `/work` から始め、report issue も `/work #N` 経由で read-only workflow へ送る。`/work`（および `/task`）のゴールは ready PR の作成までであり、PR レビューコメント対応は `/review-resolve` が担う。根拠: `CLAUDE.md`, `commands/work.md:49-68`
- report issue 以外は docs 変更要否を単一質問として扱う。根拠: `commands/work.md:84-115`, `CLAUDE.md`
- docs 同期は `git diff` を事実として扱う。根拠: `commands/docs-sync.md:1-10`, `CLAUDE.md:35`
- L0 は `/docs-sync` では更新せず、設計方針の再観測時に `/init-docs` が更新する。根拠: `commands/init-docs.md:104-122`, `commands/docs-sync.md:86-88`
