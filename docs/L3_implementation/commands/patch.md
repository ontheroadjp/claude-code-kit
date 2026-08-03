# /patch specification

## 目的・役割

`commands/patch.md` は `commands/work.md` から委譲される、**docs 変更を伴わない軽微な修正専用のワークフロー**である。issue 不要・PR 不要・docs-sync 不要の最小フローで、`patch/<slug>` ブランチに変更をコミットし、ユーザーが自分で fast-forward merge する。

前提が崩れた場合（docs 変更が必要になった、スコープが広がった等）は task フローへエスカレーションする。

根拠: `commands/patch.md:1-8`

## 動作の概要

3 Step で構成される（Phase 3 は報告のみ）:

```
Step 1: 現状調査の引き継ぎと補完（L3 per-file doc の Read を含む）
Step 2: プラン確認（必須・スキップ不可）
Step 3: 実行（ブランチ作成 → 変更 → commit）
Phase 3: 報告（ff-merge 手順を案内）
```

根拠: `commands/patch.md:13-76`

## 主要なフロー

### Step 1: 現状調査の引き継ぎと補完

work.md の調査結果を引き継ぎ、プラン確認に必要な情報が不足している場合のみ補完する。

**変更対象ファイルが確定したら、`docs/L3_implementation/<対象ファイルパス>.md` が存在する場合は必ず Read する。** 設計意図・現状仕様を把握してから Step 2 へ進む。

存在しない場合はスキップ。patch フローは L3 per-file doc を**作成しない**（docs 変更が必要になった場合は task フローへエスカレーションする）。

根拠: `commands/patch.md:15-26`

### Step 2: プラン確認（必須・スキップ不可）

以下を提示してユーザーの明確な許可を得る:

- 変更内容サマリ
- 利用ツール（`tool:git_write`）
- 新規作成・編集ファイルの絶対パス

ユーザーから OK が出た後:
1. `$CLAUDE_CODE_SESSION_ID`（Codex は `$CODEX_THREAD_ID` のハッシュ）から自セッションの `session-approved` パスを直接導出し、`tool:git_write` と対象ファイルの絶対パスを書き込む（1 度だけ）

根拠: `commands/patch.md:21-40`

### Step 3: 実行

1. `git checkout -b patch/<slug>` でブランチを作成する
2. ソースコードを修正する場合は言語対応の coding コマンド（`commands/coding-*.md`）を Read する
3. 変更を実施する（ユーザー確認不要）
4. `/git-commit` を実行する（`issue_number=none`, `allowed_types=[fix, refactor, chore, style, test, docs]`、`feat` は不可）

根拠: `commands/patch.md:45-59`

### Phase 3: 報告

変更内容サマリと以下の ff-merge 手順をユーザーに報告する:

```bash
git checkout main
git merge --ff patch/<slug>
git push origin main
git branch -d patch/<slug>
```

報告後、`git checkout main` で main に戻る。

根拠: `commands/patch.md:63-76`

## 設計上の決断

### patch フローが L3 per-file doc を作成しない理由

patch は「docs 変更を伴わない軽微な修正」に限定されている。L3 per-file doc の作成・更新は docs/* への変更であり、patch の前提（docs 変更不要）と矛盾する。

L3 per-file doc の更新が必要になるほど重要な変更であれば、それは task フローへのエスカレーション条件（docs 変更が必要になった）に該当する。

### patch フローが L3 per-file doc を Read する理由

軽微な修正であっても、対象ファイルの設計意図・制約を把握せずに変更すると意図しない挙動を壊すリスクがある。読み取り専用操作（Read）は自動承認されるため、コストなく設計意図を確認できる。

### `feat` コミットを patch フローで禁止する理由

patch は新機能追加ではなく既存機能の軽微な修正・改善を対象とする。`feat` が必要な変更はスコープが patch の範囲を超えており、task フローで正式に管理すべきである。

## エスカレーション（patch → task）

以下のいずれかに該当する場合、task フローに引き継ぐ:

- docs への追加・変更・削除が必要になった
- 変更範囲が当初想定より大幅に広がった
- 影響や副作用が読み切れず、正式なレビュー・追跡が必要と判断した
- ユーザーから追加指示があり、スコープが patch の範囲を超えた

**引き継ぎ手順:**
1. 未コミット変更があれば `/git-commit` を実行する
2. ユーザーにエスカレーション理由を報告する
3. issue ドラフトを作成して `gh issue create` する（「patch で実施済みの変更」と「追加スコープ」を記載）
4. `commands/task.md` を Read し、Phase 1 Step 2 から継続する（ブランチ再利用）

issue draft の `${TEMPLATES_DIR}/issue.md` は実行 agent に応じ、Claude Code では `~/.claude/templates`、Codex CLI では `~/.codex/templates` から解決する。

根拠: `commands/patch.md:9-11`, `commands/patch.md:84-108`

## 統合ポイント

- 呼び出し元: `commands/work.md`（ルーティング判定後）
- 呼び出すもの: `/git-commit`
- エスカレーション先: `commands/task.md`（Phase 1 Step 2 から）
- issue template: `${TEMPLATES_DIR}/issue.md`

## 注意事項

- session-approved への追記は hook がブロックするため、Step 2 で全スコープを確定させてから 1 度だけ書き込む
- patch フローに issue・PR は不要。ユーザーが手動で ff-merge する設計（軽量さを保つため）
- session ID は `${STATE_ROOT}/current-session-approved-path`（共有ポインタファイル）を経由せず、`$CLAUDE_CODE_SESSION_ID` から直接導出する（issue #210。複数セッション同時実行時の混線を防ぐため）

## 変更履歴（git log より自動生成）

- db6d6c3 fix(#210): resolve session id from env instead of a shared pointer file
- 27f1861 feat(#76): install templates for claude and codex
- 17c844b feat(#163): introduce L3 per-file docs and enforce reading them in task/patch flows
- 89d5fad feat(#157): move git-commit to commands/, add skill wrapper, update all callers to /git-commit
- 028b3af fix(#136): announce session-approved path from hook so Claude can locate it
- 13dbefd refactor: reduce duplicate file reads across work/task/patch/codex-review flows
- dd29feb feat(#129): store session approvals per session
- 4e742c9 fix(#118): guard session-approved against mid-session scope expansion
- 83374dc feat(#108): add session-based approval to eliminate double-confirmation prompts
- 6b6ddeb feat(#96): add coding skill usage instruction to task.md and patch.md
