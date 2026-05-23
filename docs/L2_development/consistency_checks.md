# Consistency Checks

このファイルは `/init-docs` Phase 4 の整合性検証結果を記録する。

最終実行: 2026-05-23

---

## 4-1. docs → 実体 の検証

### 参照パスの実在確認

| docs で参照したパス | 実在 | 備考 |
|---------------------|------|------|
| `task.md` | ✅ | ルート直下に実在 |
| `patch.md` | ✅ | ルート直下に実在 |
| `docs-sync.md` | ✅ | ルート直下に実在 |
| `init-docs.md` | ✅ | ルート直下に実在 |
| `docs/.ai/repo.profile.json` | ✅ | docs/.ai/ 下に実在 |
| `templates/issue.md` | ✅ | templates/ 下に実在 |
| `templates/pr.md` | ✅ | templates/ 下に実在 |
| `~/.claude/commands/` | ✅ | シンボリックリンク群として実在（グローバルデプロイ先） |
| `docs/L1_project/` | ✅ | 実在 |
| `docs/L2_development/` | ✅ | 実在 |
| `docs/L3_implementation/` | ✅ | 実在 |
| `legacy/` | ✅ | 14 ファイルが実在 |

### 旧 docs で参照していたが現在は legacy/ に移動済みのファイル

以下のファイルはルート直下に存在しない（legacy/ に移動済み）:
- `fix.md`, `create-test.md`, `init-test.md`, `test-balance.md`
- `init-git.md`, `git-clean.md`, `own-task.md`, `issue.md`

新 docs はこれらへの参照を含まない。

---

## 4-2. repo.profile.json ↔ docs の突合

- `repo.profile.json.doc_roots`: `docs/L1_project`, `docs/L2_development`, `docs/L3_implementation` — docs 構造と一致 ✅
- `repo.profile.json.commands`: 空 — docs でも「実行コマンドなし」と記述（一致） ✅
- `repo.profile.json.active_commands`: task.md, patch.md, docs-sync.md, init-docs.md — docs で同一の 4 本を記述 ✅
- `repo.profile.json.external_cli_deps`: git, gh — docs でも外部 CLI 依存として記述 ✅
- `repo.profile.json.deploy.method`: symlink — docs で `.claude/commands/` のシンボリックリンクとして記述 ✅

---

## 4-3. CI 定義との整合性確認

- `.github/workflows/` は存在しない（CI なし）。確認済み。
- CI との整合性チェック対象なし。

---

## 4-4. 根拠表記の正規化

- docs 内の断定文には `ファイル名:行番号` または `ファイル名:セクション名` の形式で根拠を記載済み。
- 根拠を示せない断定は記載していない。

---

## 4-5. 未確認事項

現時点で未確認の事項はない。

以前の版で「未確認」としていた以下の事項は解消済み:
- CI 定義: `.github/workflows/` の不在を直接確認 → CI なし（確定）
- 実行ランタイム: このリポジトリは Markdown 仕様のみ → ランタイムなし（確定）

---

## 4-6. フェーズ完了条件（Done Criteria）判定

| 条件 | 判定 |
|------|------|
| docs に記載された事実が実体と矛盾していない | ✅ |
| repo.profile.json と docs が相互に説明可能 | ✅ |
| CI 定義と docs の手順が一致している | ✅（CI なし、docs も CI 手順を断定しない） |
| 未確認事項が明示的に分離されている | ✅（未確認事項なし） |

**判定: 完了**
