# Specification Summary

## 対象

このサマリは、アクティブなコマンド仕様ファイル（`commands/` 配下 4 本 + templates/ 2 本）および `hooks/` の要点を、断定可能な事実のみで整理したもの。

---

## 1. `commands/task.md` — 実装フロー（主コマンド）

### 概要
全ファイル変更のエントリポイント。内部でルーティング判定を行い、patch フローまたは task フローを実行する。ユーザーは常に `/task` を呼ぶ。
- 根拠: `commands/task.md:1-9`

### ルーティング判定（main ブランチの場合）
単一質問: 「この変更で `docs/*` への追加・変更・削除が必要か？」
- 不要 → patch フロー（`commands/patch.md` のワークフローを実行）
- 必要 → task フロー（issue → 実装 → ドラフト PR → /docs-sync 自動実行）
- 根拠: `commands/task.md`（ルーティング判定節）

### patch フロー
```
patch.md のワークフローを実行（G-2 通過済みとして扱う）
```
エスカレーション: 実行中にドキュメント変更が必要と判明した場合 → issue 生成 → task Step 0 へ
- 根拠: `commands/task.md`（patch フロー節）

### task フロー（Phase 1）
- Step 0: issue 確認または自動生成（`commands/templates/issue.md` 使用）
- Step 1: 現状調査（スキップ不可）
- Step 2: プラン策定（ユーザー許可必須）
- Step 3: 実装・コミット（コミット前チェック実施 → `<type>(#<issue>): <short description>`）
- 根拠: `commands/task.md`（Phase 1 節）

### task フロー（Phase 2）
- ドラフト PR 作成（`commands/templates/pr.md` 使用、`--body-file -` で本文渡し）
- 作成後 `/docs-sync` を自動実行（docs・README.md 更新 → PR 公開まで完結）
- 根拠: `commands/task.md`（Phase 2 節）

### task フロー（Phase 3）
- 最終報告（実装ファイル・テスト・issue URL・PR URL）
- 根拠: `commands/task.md`（Phase 3 節）

### ゲート
- G-1: `docs/.ai/repo.profile.json` の存在
- G-2: main ブランチかつワークスペースがクリーン（差分は stash で退避）
- 根拠: `commands/task.md`（G-1/G-2 節）

---

## 2. `commands/patch.md` — 軽微修正フロー

### 概要
ドキュメント変更を伴わない軽微な修正専用。issue/PR 不要。
- 根拠: `commands/patch.md:1-8`

### ワークフロー
1. ルーティング判定（docs 変更が必要なら `/task` へ誘導して終了）
2. branch 作成（`patch/<slug>`）
3. 変更・コミット（コミット前チェック実施 → 複数 OK、Conventional Commits 形式）
4. ユーザーに ff-merge 手順を通知して main に戻る
- 根拠: `commands/patch.md`（Phase 1–3）

### エスカレーション（→ task フロー）
実行中にドキュメント変更が必要と判明した場合:
1. 現時点の変更をコミット
2. `commands/templates/issue.md` から issue を作成
3. `/task` Phase 1 Step 2（プラン策定）から継続
4. ブランチは `patch/<slug>` のまま再利用
- 根拠: `commands/patch.md`（エスカレーション節）

### ゲート
- G-1: `docs/.ai/repo.profile.json` の存在
- G-2: main ブランチにいること
- G-3: ワークスペースがクリーン（差分は stash で退避）
- 根拠: `commands/patch.md:11-24`

---

## 3. `commands/docs-sync.md` — ドキュメント同期フロー

### 概要
git diff を事実として docs および README.md を最小更新し、ドラフト PR を公開する。全体再構築は禁止。
- 根拠: `commands/docs-sync.md:1-10`

### ワークフロー
1. PR ステータス確認（`--json isDraft,number,url`）→ 存在確認後に本文取得
2. `git diff --name-only` で変更ファイルを特定
3. PR 本文から `/docs-sync への引き継ぎ事項` を読み取る
4. 対象ファイルの targeted diff を取得し、docs・README.md 更新対象を確定
5. HARD STOP 判定（全体再構築が必要な場合は `/init-docs` を促して終了）
6. docs・README.md を最小更新（コミット前チェック実施 → コミット）
7. ドラフト PR を公開（`gh pr ready`）
- 根拠: `commands/docs-sync.md`（各フェーズ）

### HARD STOP 条件
以下のいずれかで `/init-docs` を要求して終了:
- (A) 新規主要レイヤ/トップレベル構造の追加疑い
- (B) 起動経路・エントリポイント変更の疑い
- (C) 10 ファイル以上かつ 3 ドメイン以上の広範な変更
- 根拠: `commands/docs-sync.md`（各 HARD STOP 節）

---

## 4. `commands/init-docs.md` — ドキュメント初期化フロー

### 概要
リポジトリ実態の全体把握と設計ドキュメント再構築。重い初期化コマンド。
- 根拠: `commands/init-docs.md:1-8`

### ワークフロー（5 フェーズ）
1. プロジェクト分析（ディレクトリ・技術スタック・エントリポイント・機能・依存）
2. `docs/.ai/repo.profile.json` 生成（事実のみ、補完禁止）
3. docs 生成（L0/L1/L2/L3）
4. 整合性検証（docs↔実体、docs↔repo.profile.json、CI 整合）
5. AGENTS.md 更新
- 根拠: `commands/init-docs.md:39-222`

### 再実行トリガー
- `/docs-sync` が HARD STOP を検知
- docs が現状を説明できなくなった
- 新規レイヤ導入・エントリポイント変更の疑い
- 根拠: `commands/init-docs.md:9-19`

---

## 5. `commands/templates/issue.md` — issue 本文テンプレート

使用コンテキスト:
- `commands/task.md` Step 0（issue 自動生成時）
- `commands/patch.md` エスカレーション時
- 根拠: `commands/task.md`（Step 0 節）, `commands/patch.md`（エスカレーション節）

セクション: 概要・背景・作業スコープ・完了条件（+ エスカレーション時: /patch 実施済み変更・追加スコープ）

---

## 6. `commands/templates/pr.md` — PR 本文テンプレート

使用コンテキスト: `commands/task.md` Phase 2（ドラフト PR 作成時）
- 根拠: `commands/task.md`（Phase 2 節）

セクション: 実装サマリ・変更ファイルと内容・変更の種別・/docs-sync への引き継ぎ事項・留意点

---

## 7. `hooks/log-token-usage.sh` — token 使用量ログ hook

Claude Code の Stop hook として `~/.claude/settings.json` から呼び出される。
- 動作: stdin から `transcript_path` / `session_id` を取得し、JSONL トランスクリプト内の全 assistant エントリの `message.usage` を集計して `~/.claude/token-usage.log` に追記する
- 依存: `bash`, `jq`
- 根拠: `hooks/log-token-usage.sh:1-28`

---

## 未確認事項

- CI 定義: `.github/workflows/` が存在しない（CI なし）。確認済み。
- 実行ランタイム: このリポジトリ自体は Markdown + Bash のみ。アプリケーションランタイムなし。確認済み。
- `commands/docs-sync.md` の HARD STOP 条件 (C)「10 ファイル以上かつ 3 ドメイン以上」は AI の判断に委ねられる。
