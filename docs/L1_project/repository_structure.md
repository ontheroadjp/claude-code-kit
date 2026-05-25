# Repository Structure

## 現在のディレクトリ構造（観測結果）

```
claude-code-kit/
├── CLAUDE.md                        # AI 運用起点。Claude Code が全セッションで自動ロード
├── README.md                        # 人間向けドキュメント。インストール手順・コマンド一覧
├── .gitignore                       # .DS_Store, .claude/, logs/ を除外
├── commands/                        # アクティブコマンド仕様（Markdown）
│   ├── task.md                      # メインエントリポイント: patch/task フロー振り分け
│   ├── patch.md                     # 軽微修正フロー（docs 変更不要な場合）
│   ├── docs-sync.md                 # ドキュメント同期 + ドラフト PR 公開
│   ├── init-docs.md                 # ドキュメント全体再構築
│   └── templates/
│       ├── issue.md                 # GitHub issue 本文テンプレート
│       └── pr.md                    # GitHub PR 本文テンプレート
├── partials/                        # commands/* から Read 経由で参照される共通部品
│   └── git-commit.md                # コミット手順（diff 取得・前チェック・メッセージ生成）
├── hooks/                           # Claude Code hook スクリプト群
│   ├── log-token-usage.sh           # Stop: token usage・セッション名・コストをログ記録
│   ├── log-access-prompt.sh         # UserPromptSubmit: ユーザー指示をセッション一時ファイルに保存
│   ├── log-access-tool.sh           # PostToolUse: Read/Glob/Grep/Edit/Write をフェーズ別に追跡
│   └── log-access-stop.sh           # Stop: フェーズ別アクセスログを logs/YYYY-MM/access.log に追記
├── logs/                            # アクセスログ出力先（内容は .gitignore 対象、.gitkeep のみ追跡）
├── scripts/                         # 手動実行スクリプト群
│   └── show-token-usage.sh          # token-usage.log を複数モードで表示・集計
└── docs/                            # 設計ドキュメント（/init-docs が生成・/docs-sync が更新）
    ├── .ai/
    │   └── repo.profile.json        # AI 運用の機械可読プロファイル
    ├── L0_concept/                  # プロダクトコンセプト・設計ポリシー（WHY 層）
    │   ├── concept.md               # 目的・解決する問題・対象ユーザー・設計上の制約
    │   └── policy.md                # 技術選定・セキュリティ・パフォーマンス・禁止事項
    ├── L1_project/                  # プロジェクト全体像
    │   ├── project_overview.md
    │   └── repository_structure.md  # このファイル
    ├── L2_development/              # 開発・運用手順
    │   ├── operation_model.md
    │   └── consistency_checks.md
    └── L3_implementation/           # 実装仕様サマリ
        └── specification_summary.md
```

根拠: 2026-05-24 時点のディレクトリ実体を直接確認（`find` コマンドで全ファイル列挙）。

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
Claude Code のカスタムスラッシュコマンド仕様（Markdown）。`~/.claude/commands/` へのシンボリックリンクでグローバルデプロイされる。**Claude はこの経路のみを使用する。**
- 根拠: `README.md:30-40`, `~/.claude/commands/` 内 symlink 実体確認済み

| ファイル | スラッシュコマンド | 役割 |
|---|---|---|
| `task.md` | `/task` | 全ファイル変更のエントリポイント。docs 変更要否でルーティング |
| `patch.md` | `/patch` | docs 変更不要な軽微修正。branch + commit → ユーザーが ff-merge |
| `docs-sync.md` | `/docs-sync` | git diff を事実として docs・README.md を最小更新。ドラフト PR を公開 |
| `init-docs.md` | `/init-docs` | リポジトリ実態の全体観測とドキュメント再構築 |

### `commands/templates/`
issue・PR 本文のテンプレート。コマンドから `~/.config/claude-code-kit/templates/` として参照される（Claude / Codex 共通パス）。
- 根拠: `commands/task.md:75,130`, `commands/patch.md:103`

### `partials/`
`commands/*.md` から Read 経由でのみ参照される共通テキスト部品。スラッシュコマンドとしては登録されない（Claude Code のコマンド検出は `commands/` 配下のみを対象とするため、`partials/` 配下のファイルは自動的にコマンド化されない）。複数のコマンドで重複していた手順を一箇所に集約し、保守時の修正漏れを防ぐことを目的とする。

| ファイル | 役割 | 呼び出し元 |
|---|---|---|
| `git-commit.md` | ステージ済み diff の取得、コミット前チェック（個人情報・IP・ドメイン・絶対パス）、Conventional Commits 形式のメッセージ生成、コミット実行 | `commands/task.md`, `commands/patch.md`, `commands/docs-sync.md` |

- 根拠: `partials/git-commit.md:1-3`（スラッシュコマンドではない旨を明示）, `commands/task.md`・`commands/patch.md`・`commands/docs-sync.md` 内の Read 参照箇所

### `skills/`
Codex 向けのスキルエントリポイント。各サブディレクトリに `SKILL.md` を持ち、対応する `commands/*.md` を読んで実行するラッパーとして機能する。
**Claude では使用しない**（`~/.claude/skills/` への symlink は張らない）。Codex がスキルとして直接参照する。
- 根拠: `skills/*/SKILL.md`（各スキルの Source Of Truth 宣言）

### `hooks/`
Claude Code の hook スクリプト群。`~/.claude/hooks/` へのシンボリックリンクでデプロイされ、`~/.claude/settings.json` から呼び出される。
- `log-token-usage.sh`: Stop hook。JSONL トランスクリプトを読み取り、token usage・セッション名・推定コスト（`cost_usd`）を集計して `~/.claude/token-usage.log` に追記する
- `log-access-prompt.sh`: UserPromptSubmit hook。ユーザー指示を `/tmp/claude-access-sessions/{session_id}.prompt` に保存する
- `log-access-tool.sh`: PostToolUse hook。Read/Glob/Grep/Edit/Write を捕捉し、work.md・task.md・patch.md・docs-sync.md・init-docs.md の読み込みでフェーズを切り替えながらアクセス先を `/tmp/claude-access-sessions/{session_id}.json` に蓄積する
- `log-access-stop.sh`: Stop hook。セッション中に `/work` が呼ばれた場合のみ、フェーズ別アクセスログを `logs/YYYY-MM/access.log` に追記し、一時ファイルを削除する
- 根拠: `hooks/log-token-usage.sh`, `hooks/log-access-*.sh`, `~/.claude/settings.json`

### `scripts/`
手動実行スクリプト群。hook が出力したログを分析・表示するツールを置く。
- `show-token-usage.sh`: `~/.claude/token-usage.log` を読み取り、複数モードで表示・集計する（`--sum` / `--model` / `--cost` / `--project` / `--time` / `--anomaly`）
- 根拠: `scripts/show-token-usage.sh`

### `docs/`
`/init-docs` が生成し `/docs-sync` が追随する設計ドキュメント群。4層構造で責務を分割する。
- `L0`: プロダクトコンセプト・設計ポリシー（WHY 層）。`/docs-sync` では更新しない
- `L1`: プロジェクト全体像（構成・コマンド概要）
- `L2`: 開発・運用手順（フロー・整合ルール）
- `L3`: 実装仕様サマリ（コマンド別仕様要約）
- 根拠: `commands/init-docs.md`（Phase 3 ドキュメント生成定義）

### `docs/.ai/repo.profile.json`
AI 運用の機械可読プロファイル。アクティブコマンドのパス・テンプレートパス・hooks・外部 CLI 依存・デプロイ方式を記録する。`primary_docs` キーで調査フェーズの起点ドキュメント（`investigation`: 責務サマリ、`structure`: ディレクトリ構造）を直接参照できる軽量 SSOT として機能する。
- 根拠: `docs/.ai/repo.profile.json:1-35`

## デプロイ構成

このリポジトリは実行コードを持たない。すべての成果物はシンボリックリンクで Claude Code のグローバル設定ディレクトリに展開される。

**原則: `~/.claude/` 配下には実体ファイルを置かない。全て本リポジトリへのシンボリックリンクとする。**
このリポジトリが single source of truth であり、`~/.claude/` はその参照点に過ぎない。

| 対象 | リポジトリ内パス | デプロイ先（symlink） | 対象ツール |
|---|---|---|---|
| コマンド群 | `commands/*.md` | `~/.claude/commands/*.md` | Claude |
| 共通部品 | `partials/*.md` | なし（symlink 不要、commands から Read で参照） | Claude |
| スキル群 | `skills/*/` | なし（symlink 不要） | Codex |
| テンプレート | `commands/templates/` | `~/.config/claude-code-kit/templates/` | 共通 |
| AI 運用指示 | `CLAUDE.md` | `~/.claude/CLAUDE.md` | Claude |
| hooks | `hooks/*.sh` | `~/.claude/hooks/*.sh` | Claude |

- 根拠: `README.md:30-75`（Installation セクション）

## エントリポイント

- ユーザー向け起点: `/task`（`commands/task.md`）。内部でルーティング判定を行い `/patch` フローまたは task フローに分岐する
- アプリケーション的な `main/app/server` 実装エントリは存在しない（Markdown 仕様リポジトリのため）
- 根拠: `CLAUDE.md:13`
