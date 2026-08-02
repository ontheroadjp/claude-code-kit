# commands/

Claude Code および Codex CLI が読む Markdown 形式のコマンド仕様を置くディレクトリ。

## 仕組み

`install.sh` が各 `.md` ファイルを `~/.claude/commands/` と `~/.codex/commands/` に symlink する。
Claude Code では `/コマンド名` で、Codex CLI では `/コマンド名` または skill 経由で呼び出せる。

## エントリポイントとルーティング

全作業の入り口は `/work`（`work.md`）。report issue を先に分岐し、それ以外は2段階でルーティングする:

```
/work
├─ report label の issue
│   └─ /report-review (report-review.md)  →  read-only 評価を標準出力
└─ その他
    ├─ issue 起点、または docs/* の変更が必要
    │   └─ /task (task.md)  →  /docs-sync  →  /git-pr
    └─ docs 変更不要な軽微修正
        └─ /patch (patch.md)
```

PR レビューコメント対応は `/review-resolve`（`review-resolve.md`）が独立したエントリポイントとなる。

## コマンド一覧

| ファイル | コマンド | 役割 |
|---|---|---|
| `work.md` | `/work` | 全作業の通常入口。report issue、task、patch のルーティング判定を行う |
| `report-review.md` | `/report-review` | report issue を read-only で評価し、意見と提案を標準出力へ提示 |
| `task.md` | `/task` | docs 変更を伴う実装フロー。issue 自動生成〜実装〜ドラフト PR 作成まで |
| `patch.md` | `/patch` | docs 変更不要の軽微修正フロー。branch + commit → ユーザーが main へ ff-merge |
| `docs-sync.md` | `/docs-sync` | git diff を事実として docs を最小更新し commit する |
| `init-docs.md` | `/init-docs` | repo 再観測・設計ドキュメント再構築（重い初期化） |
| `new-issue.md` | `/new-issue` | 漠然としたアイデアから issue を生成する任意 pre-/work ステップ |
| `review-resolve.md` | `/review-resolve` | PR レビューコメントへの対応専用エントリポイント |
| `pr-review.md` | `/pr-review` | 別 AI agent による PR レビューと承認済みスコープ内の修正ループ |
| `triage-issues.md` | `/triage-issues` | open issue をドキュメントと照合して分類するスタンドアロン入口 |
| `codex-review.md` | `/codex-review` | Codex CLI で PR をレビューし approve/request-changes を投稿 |
| `git-commit.md` | `/git-commit` | コミット作成手順（WIP 正規化・Conventional Commits 形式） |
| `git-pr.md` | `/git-pr` | `git push` と `gh pr create` を担う単一責任コマンド |
| `coding-general.md` | `/coding-general` | 言語非依存のコーディング原則 |
| `coding-py.md` | `/coding-py` | Python 固有のコーディングルール |
| `coding-js.md` | `/coding-js` | JavaScript 固有のコーディングルール |
| `coding-ts.md` | `/coding-ts` | TypeScript 固有のコーディングルール |

## 使い方

```bash
# インストール（symlink 作成）
./install.sh

# Claude Code でコマンドを呼び出す例
/work
/work #175
/review-resolve #174
```

コマンドファイルは Markdown で記述されており、AI が Read して手順に従って実行する。
直接編集する場合は symlink 先ではなくこのリポジトリの実体ファイルを編集すること。
