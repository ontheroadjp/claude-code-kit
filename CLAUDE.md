# CLAUDE.md

このファイルは AI 運用の起点となる情報をまとめる。Claude Code がこのリポジトリで作業する際はここを先に読む。

## このリポジトリについて

作業開始時に `README.md` の以下のセクションを読み、リポジトリ固有のコンテキストを把握すること:

- **Features / Commands**: アクティブな機能・コマンド一覧
- **Design Principles**: 守るべき設計制約
- **Usage**: run/test コマンド・開発手順

## Custom Command の使い分け（AI 向けルール）

**重要: ワークフローの入り口は2つある。PR レビューコメント対応なら `/review-resolve`、それ以外の全作業は直ちに `/work` を呼ぶこと。調査は `/work` 内で行う。**

- **review-resolve.md**: PR レビューコメント対応専用のエントリポイント。`/work` を経由せず自己完結（checkout → 実装 → commit → push → 返信）。ユーザーが `/review-resolve #N` で直接呼び出す。
- **work.md**: review-resolve 以外の全作業のエントリポイント。ゲート確認・ワークスペース管理・現状調査・ルーティング判定を行い、task.md または patch.md へ委譲する。
  - docs 変更不要 → patch.md を Read して patch フロー（issue/PR なし、branch + commit → ユーザーが ff-merge）
  - docs 変更あり → task.md を Read して task フロー（issue 自動生成 → 実装 → ドラフト PR 作成 → /docs-sync へ引き継ぎ）
- **task.md**: docs 変更を伴う実装専用。work.md から Read 経由で呼ばれる。直接呼ばれることは想定しない。
- **patch.md**: ドキュメント変更を伴わない軽微な修正専用。work.md から Read 経由で呼ばれる。直接呼ばれることは想定しない。
- **docs-sync.md**: git diff を事実として docs を最小更新し、ドラフト PR を公開する。task フロー完了後に呼ぶ。HARD STOP 時は /init-docs を要求して終了する。
- **init-docs.md**: リポジトリ実態の全体把握と設計ドキュメント再構築。重い初期化。docs-sync が説明不能になった時点でここに戻る。

## 重要な設計原則

- **symlink-only 原則**: `~/.claude/` 配下には実体ファイルを置かず、全て本リポジトリへの symlink とする。このリポジトリが single source of truth。
- ルーティング判定は単一質問: 「この変更で `docs/*` への追加・変更・削除が必要か？」
- issue は task フローのみ必須（patch フローには不要）
- task フローのコミット形式: `<type>(#<issue number>): <short description>` (Conventional Commits)
  - Example: `feat(#23): implement user auth endpoint`
- ワークスペースのクリーン化は stash で行う（破壊的操作禁止）
- git diff が事実。AI の要約・解釈は補助情報にとどめる

## テンプレートの場所

- `templates/issue.md` → `~/.config/claude-code-kit/templates/issue.md` としても参照可能
- `templates/pr.md` → `~/.config/claude-code-kit/templates/pr.md` としても参照可能
- `templates/readme.md` → 新規リポジトリの README.md 雛形

## リポジトリへの操作ルール（必須）

このリポジトリに影響する操作を行う際は、以下のルールに従うこと。

### ファイル編集・追加・削除の操作
**ファイルを編集・追加・削除する際は、`/review-resolve` フロー内を除き、必ず `/work` を実行すること。**
直接編集は禁止。`/work` 経由でルーティング判定・ブランチ作成・コミットを行う。
`/review-resolve` フロー内での実装は、PR ブランチ上で直接行い commit・push まで完結させる。

### npm 関連の操作
npm は遅延ロードされます。npm を利用する際は最初に `npm --version` を実行して npm をロードします。

### /work フロー対象外の操作（git 管理操作）
以下の操作は `/work` フローに乗らないが、実行前に必ず理由を説明しユーザーの明示的な確認を取ること:

- git 履歴の書き換え（`filter-repo` / `filter-branch` 等）
- `git push --force`
- ブランチの強制削除（`git branch -D`）
- その他、不可逆または共有状態に影響する git 操作

## このリポジトリへの変更作業

このリポジトリ自体を変更する場合も `/work` を呼ぶ。ただし:
- run/build/test コマンドは存在しない（Markdown + Bash のみ）
- 変更後は `docs/` の更新が必要になることが多い（/docs-sync を呼ぶ）
- シンボリックリンクは自動更新される（リンク先の実体を変更するだけでよい）
