# CLAUDE.md

このファイルは AI 運用の起点となる情報をまとめる。Claude Code がこのリポジトリで作業する際はここを先に読む。

## このリポジトリについて

作業開始時に `README.md` の以下のセクションを読み、リポジトリ固有のコンテキストを把握すること:

- **Features**: アクティブな機能・コマンド一覧
- **Design Principles**: 守るべき設計制約
- **Usage**: run/test/build コマンド・開発手順

## Custom / Command の使い分け（AI向けルール）

**重要: PR レビューコメントへの対話対応は `/review-resolve`、PR 作成後の別 agent による自律レビューは `/pr-review`、それ以外の全作業は直ちに `/work` を呼ぶこと。漠然としたアイデアから issue を作成したい場合のみ任意で `/new-issue` を先に使い、その後 `/work` で実装に入る。調査は `/work` 内で行う。**

- **review-resolve.md**: PR レビューコメント対応専用のエントリポイント。`/work` を経由せず自己完結（checkout → 実装 → commit → push → 返信）。ユーザーが `/review-resolve #N` で直接呼び出す。
- **pr-review.md**: PR 作成後のレビュー専用エントリポイント。実装元とは別の agent がレビューし、元 agent が承認済みスコープ内の指摘を PR ブランチ上で修正・commit・push・再レビューする。merge は行わず人間判断に残す。
- **work.md**: review-resolve / pr-review 以外の全作業のエントリポイント。ゲート確認・ワークスペース管理・現状調査・ルーティング判定を行い、task.md または patch.md へ委譲する。
  - docs 変更不要 → patch.md を Read して patch フロー（issue/PR なし、branch + commit → ユーザーが ff-merge）
  - docs 変更あり → task.md を Read して task フロー（issue 自動生成 → 実装 → ドラフト PR 作成 → /docs-sync へ引き継ぎ）
- **new-issue.md**: 漠然としたアイデアから 1 件または複数件の整形された issue を生成する任意の pre-`/work` エントリポイント。issue 作成のみで実装は行わない。
- **triage-issues.md**: open issue を現状 docs と照合し、stale / inconsistent / duplicated / unclear / ready に分類するスタンドアロン入口。issue 操作はユーザー承認後のみ行う。
- **codex-review.md**: Codex CLI で PR をレビューし、`CODEX_REVIEW_TOKEN` がある場合に approve/request-changes を投稿する。変更要求時は `/review-resolve` へ引き継ぐ。
- **task.md**: ドキュメント変更を伴う実装に特化。issue 自動生成〜実装〜ドラフト PR 作成まで。docs/* は変更しない。
- **patch.md**: ドキュメント変更を伴わない軽微な修正に特化。issue/PR 不要。branch + commit → ユーザーが main へマージ。スコープが広がった場合は /task へエスカレーション。
- **docs-sync.md**: git diff を事実として docs を最小更新し、ドラフト PR を公開する。HARD STOP 時は /init-docs を要求して終了する。
- **init-docs.md**: repo の実態把握と設計ドキュメント再構築。重い初期化。docs-sync が説明不能になった時点でここに戻る。

## 重要な設計原則

- **symlink-only 原則**: `~/.claude/` 配下には実体ファイルを置かず、全て本リポジトリへの symlink とする。このリポジトリが single source of truth。
- ルーティング判定は単一質問: 「この変更で `docs/*` への追加・変更・削除が必要か？」
- issue は task フローのみ必須（patch フローには不要）
- task フローのコミット形式: `<type>(#<issue number>): <short description>` (Conventional Commits)
- ワークスペースのクリーン化は stash で行う（破壊的操作禁止）
- git diff が事実。AI の要約・解釈は補助情報にとどめる

## テンプレートの場所

- `templates/issue.md` → `~/.config/claude-code-kit/templates/issue.md` として参照する
- `templates/pr.md` → `~/.config/claude-code-kit/templates/pr.md` として参照する
- `templates/readme.md` → 新規リポジトリの README.md 雛形

## リポジトリへの操作ルール（必須）

このリポジトリに影響する操作を行う際は、以下のルールに従うこと。

### ファイル編集・追加・削除の操作
**ファイルを編集・追加・削除する際は、`/review-resolve` または `/pr-review` フロー内を除き、必ず `/work` を実行すること。**
直接編集は禁止。`/work` 経由でルーティング判定・ブランチ作成・コミットを行う。
`/review-resolve` フロー内での実装は、PR ブランチ上で直接行い commit・push まで完結させる。
`/pr-review` フロー内での実装は、PR ブランチ上で承認済みスコープ内の指摘だけを修正し、commit・必要な docs-sync・push・再レビューまで行う。PR の merge は人間が行う。

### npm 関連の操作
site は `site/` 配下で npm を使う。npm を利用する際は最初に `node --version` を実行して node をロードする。

### 一時ファイルの作成
AI agent がテスト・検証・中間生成物などで一時ファイルを作成する必要がある場合は、原則として `/tmp/claude-code-kit/$SESSION_ID/` 配下を使用すること。

- `/tmp` 直下や任意の一時ディレクトリには作成しない
- セッション終了時に Stop hook が `/tmp/claude-code-kit/$SESSION_ID/` を削除する
- 永続化が必要な成果物は一時ディレクトリではなく、作業計画で明示したリポジトリ内の対象パスに作成する

### /work フロー対象外の操作（git 管理操作）
以下の操作は `/work` フローに乗らないが、実行前に必ず理由を説明しユーザーの明示的な確認を取ること:

- git 履歴の書き換え（`filter-repo` / `filter-branch` 等）
- `git push --force`
- ブランチの強制削除（`git branch -D`）
- その他、不可逆または共有状態に影響する git 操作

## このリポジトリへの変更作業

このリポジトリ自体を変更する場合も `/work` を呼ぶ。ただし:
- コマンド仕様・hooks・skills は Markdown + Bash が中心
- `site/` は VitePress + npm で、CI は `cd site && npm run docs:build` を実行する
- 変更後は `docs/` の更新が必要になることが多い（/docs-sync を呼ぶ）
- シンボリックリンクはリンク先の実体を変更するだけで反映される
