# Repository Structure

## 現在のディレクトリ構造（観測結果）

```
agent-custom-slash-commands/
├── task.md           # アクティブコマンド: 実装フロー（patch フロー内包）
├── patch.md          # アクティブコマンド: 軽微修正フロー
├── docs-sync.md      # アクティブコマンド: ドキュメント同期フロー
├── init-docs.md      # アクティブコマンド: ドキュメント初期化フロー
├── .gitignore
├── .claude/
│   └── commands/     # コマンドファイルのコピー（同期用）
├── docs/
│   ├── .ai/
│   │   └── repo.profile.json  # リポジトリプロファイル（AI 運用の基盤）
│   ├── L1_project/
│   │   ├── project_overview.md
│   │   └── repository_structure.md
│   ├── L2_development/
│   │   ├── operation_model.md
│   │   └── consistency_checks.md
│   └── L3_implementation/
│       └── specification_summary.md
├── templates/
│   ├── issue.md      # issue 本文テンプレート
│   └── pr.md         # PR 本文テンプレート
└── legacy/           # 廃止・統合済みのコマンド仕様（参照のみ）
    └── （14ファイル）
```

根拠: 2026-05-23 時点のディレクトリ実体を直接確認。

## 各ディレクトリの責務

### ルート直下 `.md` ファイル
アクティブなコマンド仕様ファイル。AI エージェントが `/コマンド名` で呼び出す実行仕様。

### `.claude/commands/`
コマンドファイルのコピー置き場（同期用）。グローバルデプロイは `~/.claude/commands/` へのシンボリックリンクで行われる。
- `~/.claude/commands/` 内の各ファイルがルート直下の実体へのシンボリックリンクとして実在することを確認済み

### `docs/`
`/init-docs` が生成し `/docs-sync` が追随する設計ドキュメント群。3層構造で責務を分割する。
- `L1`: プロジェクト全体像（構成・コマンド概要）
- `L2`: 開発・運用手順（起動・整合ルール）
- `L3`: 実装仕様サマリ（コマンド別仕様要約）
- 根拠: `init-docs.md:98-113`（Phase 3 ドキュメント生成定義）

### `templates/`
issue・PR 本文のテンプレートファイル群。コマンドから `~/.claude/commands/templates/` として参照される。
- 根拠: `task.md:129`, `task.md:197`, `patch.md:103`

### `legacy/`
統合・廃止された旧コマンド仕様。参照専用で、アクティブなフローからは呼び出されない。

## エントリポイント

- Slash Command 仕様ファイル自体（`task.md`, `patch.md`, `docs-sync.md`, `init-docs.md`）が運用エントリポイント。
  - 根拠: 各ファイルが `/task`, `/patch`, `/docs-sync`, `/init-docs` として AI エージェントに呼び出される仕様として定義されている
- アプリケーション的な `main/app/server` 実装エントリは存在しない（Markdown 仕様リポジトリのため）。
