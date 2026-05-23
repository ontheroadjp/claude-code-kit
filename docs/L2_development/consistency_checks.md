# Consistency Checks

このファイルは `/init-docs` Phase 4 の整合性検証結果を記録する。

最終実行: 2026-05-23（hooks 追加・commands/ 移動後の再構築）

---

## 4-1. docs → 実体 の検証

### 参照パスの実在確認

| docs で参照したパス | 実在 | 備考 |
|---------------------|------|------|
| `commands/task.md` | ✅ | commands/ 下に実在 |
| `commands/patch.md` | ✅ | commands/ 下に実在 |
| `commands/docs-sync.md` | ✅ | commands/ 下に実在 |
| `commands/init-docs.md` | ✅ | commands/ 下に実在 |
| `commands/templates/issue.md` | ✅ | commands/templates/ 下に実在 |
| `commands/templates/pr.md` | ✅ | commands/templates/ 下に実在 |
| `hooks/log-token-usage.sh` | ✅ | hooks/ 下に実在 |
| `docs/.ai/repo.profile.json` | ✅ | docs/.ai/ 下に実在 |
| `CLAUDE.md` | ✅ | ルート直下に実在 |
| `~/.claude/commands/` | ✅ | シンボリックリンク群として実在（グローバルデプロイ先） |
| `~/.claude/hooks/` | ✅ | log-token-usage.sh symlink として実在 |
| `~/.claude/CLAUDE.md` | ✅ | CLAUDE.md への symlink として実在 |
| `skills/*/` | ✅ | Codex 向けスキル。`~/.claude/skills/` への symlink は張らない |
| `docs/L1_project/` | ✅ | 実在 |
| `docs/L2_development/` | ✅ | 実在 |
| `docs/L3_implementation/` | ✅ | 実在 |

---

## 4-2. repo.profile.json ↔ docs の突合

- `repo_id`: `claude-code-kit` — リポジトリ名と一致 ✅
- `doc_roots`: `docs/L1_project`, `docs/L2_development`, `docs/L3_implementation` — docs 構造と一致 ✅
- `commands`: 空 — docs でも「実行コマンドなし」と記述（一致） ✅
- `active_commands`: `commands/task.md` 他 4 本 — docs で同一のパスを記述 ✅
- `templates`: `commands/templates/issue.md`, `commands/templates/pr.md` — docs と一致 ✅
- `hooks`: `hooks/log-token-usage.sh` — docs と一致 ✅
- `external_cli_deps`: `git`, `gh`, `jq` — docs でも同 3 本を記述 ✅
- `deploy`: commands/hooks/CLAUDE.md の 3 系統を記述 — docs（README.md）と一致 ✅

---

## 4-3. CI 定義との整合性確認

- `.github/workflows/` は存在しない（CI なし）。直接確認済み。
- CI との整合性チェック対象なし。

---

## 4-4. 根拠表記の正規化

- docs 内の断定文には `ファイルパス` または `ファイルパス:行番号` の形式で根拠を記載済み。
- 行番号が変動しやすい箇所はセクション名を根拠として記載。
- 根拠を示せない断定は記載していない。

---

## 4-5. 未確認事項

現時点で未確認の事項はない。

確定済み事項:
- CI 定義: `.github/workflows/` の不在を直接確認 → CI なし（確定）
- 実行ランタイム: Markdown + Bash のみ → アプリケーションランタイムなし（確定）
- `hooks/log-token-usage.sh` の動作: 実際のトランスクリプトで動作確認済み（2026-05-23）

---

## 4-6. フェーズ完了条件（Done Criteria）判定

| 条件 | 判定 |
|------|------|
| docs に記載された事実が実体と矛盾していない | ✅ |
| repo.profile.json と docs が相互に説明可能 | ✅ |
| CI 定義と docs の手順が一致している | ✅（CI なし、docs も CI 手順を断定しない） |
| 未確認事項が明示的に分離されている | ✅（未確認事項なし） |

**判定: 完了**
