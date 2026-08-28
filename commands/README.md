# commands/

Claude Code および Codex CLI が読む Markdown 形式のコマンド仕様を置くディレクトリ。

## 仕組み

`install.sh` が各 `.md` ファイルを `~/.claude/commands/` と `~/.codex/commands/` に symlink する。
Claude Code では `/コマンド名` で、Codex CLI では対応 skill を通じて同じ specification を利用する。`commands/` は workflow definition の Source of Truth であり、Codex skill は手順を複製しない adapter である。

## Invocation authority

- **user-controlled workflow** は、ユーザーの明示意図で開始する入口である。
- **internal workflow / stage** は、上位 workflow が必要な順序で委譲する。
- **supporting capability** は、active workflow が対象技術や状況に応じて適用する。

この分類は command の配置ではなく workflow の責務を表す。具体的な分類と運用境界は `docs/L1_project/project_overview.md` および `docs/L2_development/operation_model.md` を参照する。

## エントリポイントとルーティング

実装作業の入口は `/work`（`work.md`）。agenda issue を先に分岐し、それ以外は2段階でルーティングする:

```
/work
├─ agenda label の issue
│   └─ /mtg (mtg.md)  →  人間主導の対話と意思決定
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
| `work.md` | `/work` | 実装作業の通常入口。agenda issue、task、patch のルーティング判定を行う |
| `work-multi.md` | `/work-multi` | deliberate concurrent sessions 向けに隔離 worktree で `/work` を実行する入口 |
| `task-manager.md` | `/task-manager` | 1〜3 issue を input order で処理する独立 batch workflow |
| `mtg.md` | `/mtg` | agenda issue を人間主導で検討し、必要時に `/new-issue` の起案を案内 |
| `task.md` | `/task` | docs 変更を伴う実装フロー。issue 自動生成〜実装〜ドラフト PR 作成まで |
| `patch.md` | `/patch` | docs 変更不要の軽微修正フロー。branch + commit → ユーザーが main へ ff-merge |
| `docs-sync.md` | `/docs-sync` | git diff を事実として docs を最小更新し commit する |
| `init-docs.md` | `/init-docs` | repo 再観測・設計ドキュメント再構築（重い初期化） |
| `new-issue.md` | `/new-issue` | 漠然としたアイデアから issue を生成する任意 pre-/work ステップ |
| `review-resolve.md` | `/review-resolve` | PR レビューコメントへの対応専用エントリポイント |
| `triage-issues.md` | `/triage-issues` | open issue をドキュメントと照合して分類するスタンドアロン入口 |
| `analyze-hazard-scan.md` | `/analyze-hazard-scan` | auto-approve と access のログから Issue 化候補を分析する |
| `triage-issues-for-hazard.md` | `/triage-issues-for-hazard` | hazard-candidate issue を人間審査するスタンドアロン入口 |
| `codex-review.md` | `/codex-review` | Codex CLI で PR をレビューし approve/request-changes を投稿 |
| `analyze-access.md` | `/analyze-access` | access log を集計し、重複 read の evidence と proposals を報告 |
| `analyze-auto-approve.md` | `/analyze-auto-approve` | auto-approve log を集計し、承認摩擦の evidence と proposals を報告 |
| `analyze-token-usage.md` | `/analyze-token-usage` | token-usage log を集計し、cache efficiency の evidence と proposals を報告 |
| `git-commit.md` | `/git-commit` | コミット作成手順（WIP 正規化・Conventional Commits 形式） |
| `git-pr.md` | `/git-pr` | `git push` と `gh pr create` を担う単一責任コマンド |
| `git-pr-merge.md` | `/git-pr-merge` | 明示承認済み PR を latest-main refresh・検証後に squash merge する delivery workflow |
| `concept-maker.md` | `/concept-maker` | ユーザー承認済み L0 promotion candidate を処理するスタンドアロン入口 |
| `coding-general.md` | `/coding-general` | 言語非依存のコーディング原則 |
| `coding-py.md` | `/coding-py` | Python 固有のコーディングルール |
| `coding-js.md` | `/coding-js` | JavaScript 固有のコーディングルール |
| `coding-ts.md` | `/coding-ts` | TypeScript 固有のコーディングルール |
| `coding-sh.md` | `/coding-sh` | Shell script 固有のコーディングルール（ShellCheck） |
| `coding-react.md` | `/coding-react` | React 固有の汎用ルールとアンチパターン |
| `coding-nextjs.md` | `/coding-nextjs` | Next.js 固有の汎用ルールとアンチパターン |

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
