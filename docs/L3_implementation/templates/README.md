# templates/README.md — L3 per-file doc

## 目的・役割

`templates/` ディレクトリの目的・各テンプレートファイルの構成・使用コマンドとのマッピングを説明するドキュメント。

## 動作の概要

- `issue.md`・`pr.md`・`readme.md` の構成と用途を説明
- Claude Code / Codex CLI それぞれの installed path と symlink 設定手順を記載
- `issue.md` のエスカレーション専用セクションについて言及

## 重要な設計判断

- PR タイトル・本文は英語必須という制約を明示（commands/task.md に由来）
- template 実体を repository に一元化しつつ、Claude Code は `~/.claude/templates/`、Codex CLI は `~/.codex/templates/` の symlink 経由で参照する
- directory 全体の移動や複製ではなく、installer が各 Markdown file を両 target へ link する

## 統合ポイント

- 使用コマンド: `/task`（Step 2, Phase 2）、`/new-issue`（Step 4）、`/git-pr`、`/init-docs`
- 関連: `templates/issue.md`、`templates/pr.md`、`templates/readme.md`

根拠: `templates/README.md:1-57`, `templates/issue.md:1-25`

## 変更履歴（git log より自動生成）

- 3656e6e docs(#175): add README.md to each module directory
