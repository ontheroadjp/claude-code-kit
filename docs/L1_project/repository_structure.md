# Repository Structure

## 現在のディレクトリ構造（観測結果）

```
claude-code-kit/
├── CLAUDE.md                        # AI 運用起点。Claude Code が全セッションで自動ロード
├── README.md                        # 人間向けドキュメント。インストール手順・コマンド一覧
├── .gitignore                       # .DS_Store, .claude/ を除外
├── commands/                        # アクティブコマンド仕様（Markdown）
│   ├── task.md                      # メインエントリポイント: patch/task フロー振り分け
│   ├── patch.md                     # 軽微修正フロー（docs 変更不要な場合）
│   ├── docs-sync.md                 # ドキュメント同期 + ドラフト PR 公開
│   ├── init-docs.md                 # ドキュメント全体再構築
│   └── templates/
│       ├── issue.md                 # GitHub issue 本文テンプレート
│       └── pr.md                    # GitHub PR 本文テンプレート
├── hooks/                           # Claude Code Stop hook スクリプト群
│   └── log-token-usage.sh           # セッション終了時に token usage をログ記録
└── docs/                            # 設計ドキュメント（/init-docs が生成・/docs-sync が更新）
    ├── .ai/
    │   └── repo.profile.json        # AI 運用の機械可読プロファイル
    ├── L1_project/                  # プロジェクト全体像
    │   ├── project_overview.md
    │   └── repository_structure.md  # このファイル
    ├── L2_development/              # 開発・運用手順
    │   ├── operation_model.md
    │   └── consistency_checks.md
    └── L3_implementation/           # 実装仕様サマリ
        └── specification_summary.md
```

根拠: 2026-05-23 時点のディレクトリ実体を直接確認（`find` コマンドで全ファイル列挙）。

## 各ディレクトリ・ファイルの責務

### `CLAUDE.md`
Claude Code が全セッションで自動ロードする AI 運用指示ファイル。以下を定義する:
- アクティブコマンドの一覧と使い分けルール
- ルーティング判定の単一質問（docs/* 変更要否）
- task フローのコミット形式（Conventional Commits）
- ワークスペースの扱い方（stash 優先、破壊的操作禁止）
- このリポジトリ自体への操作ルール
- 根拠: `CLAUDE.md:1-56`

### `commands/`
Claude Code のカスタムスラッシュコマンド仕様（Markdown）。`~/.claude/commands/` へのシンボリックリンクでグローバルデプロイされる。
- 根拠: `README.md:30-40`, `~/.claude/commands/` 内 symlink 実体確認済み

| ファイル | スラッシュコマンド | 役割 |
|---|---|---|
| `task.md` | `/task` | 全ファイル変更のエントリポイント。docs 変更要否でルーティング |
| `patch.md` | `/patch` | docs 変更不要な軽微修正。branch + commit → ユーザーが ff-merge |
| `docs-sync.md` | `/docs-sync` | git diff を事実として docs・README.md を最小更新。ドラフト PR を公開 |
| `init-docs.md` | `/init-docs` | リポジトリ実態の全体観測とドキュメント再構築 |

### `commands/templates/`
issue・PR 本文のテンプレート。コマンドから `~/.claude/commands/templates/` として参照される。
- 根拠: `commands/task.md:75,130`, `commands/patch.md:103`

### `hooks/`
Claude Code の Stop hook スクリプト群。`~/.claude/hooks/` へのシンボリックリンクでデプロイされ、`~/.claude/settings.json` の `hooks.Stop` から呼び出される。
- `log-token-usage.sh`: セッション終了時に JSONL トランスクリプトを読み取り、全ターンの token usage を集計して `~/.claude/token-usage.log` に追記する
- 根拠: `hooks/log-token-usage.sh:1-28`, `~/.claude/settings.json:hooks.Stop`

### `docs/`
`/init-docs` が生成し `/docs-sync` が追随する設計ドキュメント群。3層構造で責務を分割する。
- `L1`: プロジェクト全体像（構成・コマンド概要）
- `L2`: 開発・運用手順（フロー・整合ルール）
- `L3`: 実装仕様サマリ（コマンド別仕様要約）
- 根拠: `commands/init-docs.md:98-113`（Phase 3 ドキュメント生成定義）

### `docs/.ai/repo.profile.json`
AI 運用の機械可読プロファイル。アクティブコマンドのパス・テンプレートパス・hooks・外部 CLI 依存・デプロイ方式を記録する。
- 根拠: `docs/.ai/repo.profile.json:1-35`

## デプロイ構成

このリポジトリは実行コードを持たない。すべての成果物はシンボリックリンクで Claude Code のグローバル設定ディレクトリに展開される。

**原則: `~/.claude/` 配下には実体ファイルを置かない。全て本リポジトリへのシンボリックリンクとする。**
このリポジトリが single source of truth であり、`~/.claude/` はその参照点に過ぎない。

| 対象 | リポジトリ内パス | デプロイ先（symlink） |
|---|---|---|
| コマンド群 | `commands/*.md` | `~/.claude/commands/*.md` |
| テンプレート | `commands/templates/` | `~/.claude/commands/templates/` |
| AI 運用指示 | `CLAUDE.md` | `~/.claude/CLAUDE.md` |
| hooks | `hooks/*.sh` | `~/.claude/hooks/*.sh` |

- 根拠: `README.md:30-75`（Installation セクション）

## エントリポイント

- ユーザー向け起点: `/task`（`commands/task.md`）。内部でルーティング判定を行い `/patch` フローまたは task フローに分岐する
- アプリケーション的な `main/app/server` 実装エントリは存在しない（Markdown 仕様リポジトリのため）
- 根拠: `CLAUDE.md:13`
