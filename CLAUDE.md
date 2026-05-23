# CLAUDE.md

このファイルは AI 運用の起点となる情報をまとめる。Claude Code がこのリポジトリで作業する際はここを先に読む。

## このリポジトリについて

Claude Code 向けのカスタムスラッシュコマンド仕様（Markdown）のリポジトリ。
アクティブコマンドは 4 本（task.md, patch.md, docs-sync.md, init-docs.md）。
`~/.claude/commands/` へのシンボリックリンクでグローバルデプロイされる。

## Custom Command の使い分け（AI 向けルール）

- **task.md**: ユーザーは常にこれを呼ぶ。内部でルーティング判定を行い、patch フローまたは task フローを実行する。
  - docs 変更不要 → patch フロー（issue/PR なし、branch + commit → ユーザーが ff-merge）
  - docs 変更あり → task フロー（issue 自動生成 → 実装 → ドラフト PR 作成 → /docs-sync へ引き継ぎ）
- **patch.md**: ドキュメント変更を伴わない軽微な修正専用コマンド。直接呼ばれることは少なく、task.md 経由が基本。
- **docs-sync.md**: git diff を事実として docs を最小更新し、ドラフト PR を公開する。task フロー完了後に呼ぶ。HARD STOP 時は /init-docs を要求して終了する。
- **init-docs.md**: リポジトリ実態の全体把握と設計ドキュメント再構築。重い初期化。docs-sync が説明不能になった時点でここに戻る。

## 重要な設計原則

- ルーティング判定は単一質問: 「この変更で `docs/*` への追加・変更・削除が必要か？」
- issue は task フローのみ必須（patch フローには不要）
- WIP コミットマーカー: `[/task:wip] #<issue番号> <実装内容の要約>`
- ワークスペースのクリーン化は stash で行う（破壊的操作禁止）
- git diff が事実。AI の要約・解釈は補助情報にとどめる

## テンプレートの場所

- `templates/issue.md` → `~/.claude/commands/templates/issue.md` としても参照可能
- `templates/pr.md` → `~/.claude/commands/templates/pr.md` としても参照可能

## ファイル編集のルール（必須）

**このリポジトリのファイルを編集する際は、必ず `/task` を実行すること。**
直接編集は禁止。`/task` 経由でルーティング判定・ブランチ作成・コミットを行う。

## このリポジトリへの変更作業

このリポジトリ自体を変更する場合も `/task` を呼ぶ。ただし:
- run/build/test コマンドは存在しない（Markdown のみ）
- 変更後は `docs/` の更新が必要になることが多い（/docs-sync を呼ぶ）
- シンボリックリンクは自動更新される（リンク先の実体を変更するだけでよい）
