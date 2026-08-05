# skills/

Codex CLI 向けの skill wrapper を置くディレクトリ。

## 仕組み

`install.sh` が各 `skills/<name>/` ディレクトリを `~/.codex/skills/<name>/` に symlink する。
各 skill ディレクトリには `SKILL.md` が1ファイルあり、Codex CLI が `/skill-name` で呼び出したときに読み込まれる。

`SKILL.md` は対応する `commands/*.md` を **Source of Truth** として Read するよう指示するだけの薄い wrapper。
コマンドのロジックは全て `commands/` 側に集約されており、skill 側にビジネスロジックは書かない。

## ディレクトリ構造

```
skills/
├── work/
│   ├── SKILL.md    ← commands/work.md を Read して実行するよう指示
│   └── work        ← サブディレクトリ（Codex skill の構成要素）
├── task/
│   └── SKILL.md
├── patch/
│   └── SKILL.md
└── ... (commands/ と 1:1 で対応)
```

## skill 一覧

| skill ディレクトリ | 対応コマンド | 役割 |
|---|---|---|
| `work/` | `commands/work.md` | 全作業の通常入口 |
| `report-review/` | `commands/report-review.md` | report issue の read-only 評価 |
| `task/` | `commands/task.md` | docs 変更を伴う実装フロー |
| `patch/` | `commands/patch.md` | docs 変更不要の軽微修正 |
| `docs-sync/` | `commands/docs-sync.md` | docs 最小更新 |
| `init-docs/` | `commands/init-docs.md` | docs 再構築 |
| `new-issue/` | `commands/new-issue.md` | issue 生成 |
| `review-resolve/` | `commands/review-resolve.md` | PR レビューコメント対応 |
| `triage-issues/` | `commands/triage-issues.md` | issue トリアージ |
| `codex-review/` | `commands/codex-review.md` | Codex による PR レビュー |
| `git-commit/` | `commands/git-commit.md` | コミット作成 |
| `git-pr/` | `commands/git-pr.md` | push と PR 作成 |
| `coding-general/` | `commands/coding-general.md` | 言語非依存コーディング原則 |
| `coding-py/` | `commands/coding-py.md` | Python コーディングルール |
| `coding-js/` | `commands/coding-js.md` | JavaScript コーディングルール |
| `coding-ts/` | `commands/coding-ts.md` | TypeScript コーディングルール |
| `coding-sh/` | `commands/coding-sh.md` | Shell script コーディングルール（ShellCheck） |

## 使い方

```bash
# インストール（symlink 作成）
./install.sh

# Codex CLI での呼び出し例
/work
/task
/review-resolve #174
```

新しいコマンドを追加した場合は、対応する `skills/<name>/SKILL.md` も作成すること。`install.sh` は `skills/*/` を検出して自動的に symlink する。
