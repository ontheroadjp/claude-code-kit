# `commands/task.md`

## 目的・役割

`/work` から委譲される、docs 変更を伴う実装・issue・PR 作成フローを定義する。

根拠: `commands/task.md:1-205`

## 動作の概要

Phase 1 で調査、プラン承認、issue 作成、実装、テスト、L3 doc 更新、commit を行う。Phase 2 では PR 本文を準備して `/docs-sync` と `/git-pr` へ委譲する。Phase 2 の clean workspace guard は `worktree-status.sh` を利用し、隔離 worktree の自己作成 symlink を自動除外して実際の差分だけを判定する。

根拠: `commands/task.md:31-205`

## 重要な設計判断

G-2 と Phase 2 の self-created symlink 判定を同じヘルパーに委譲する。前者と後者で manifest 照合の実装・解釈が分岐しないようにするため。

## 統合ポイント

- 呼び出し元: `commands/work.md`
- 呼び出すもの: `commands/new-issue.md`、`commands/docs-sync.md`、`commands/git-pr.md`
- status helper: agent 別 `scripts/worktree-status.sh`

## 注意事項・既知の制限

helper が manifest を解決できない場合、workspace status は未フィルタの porcelain 出力として扱う。
