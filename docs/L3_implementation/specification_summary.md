# Specification Summary

## 対象

このサマリは、アクティブなコマンド仕様ファイル（ルート直下 4 本 + templates/ 2 本）の要点を、断定可能な事実のみで整理したもの。

---

## 1. `task.md` — 実装フロー（主コマンド）

### 概要
ドキュメント変更を伴う実装の主コマンド。内部でルーティング判定を行い、patch フローまたは task フローを実行する。ユーザーは常に `/task` を呼ぶ。
- 根拠: `task.md:1-9`

### ルーティング判定（main ブランチの場合）
単一質問: 「この変更で `docs/*` への追加・変更・削除が必要か？」
- 不要 → patch フロー（docs 変更なし、issue/PR なし）
- 必要 → task フロー（issue → 実装 → ドラフト PR）
- 根拠: `task.md:37-60`

### patch フロー
```
branch 作成（patch/<slug>）→ 変更・コミット → ユーザーが ff-merge
```
エスカレーション: 実行中にドキュメント変更が必要と判明した場合 → issue 生成 → task Step 0 へ
- 根拠: `task.md:61-86`

### task フロー（Phase 1）
- Step 0: issue 確認または自動生成（`templates/issue.md` 使用）
- Step 1: 現状調査（スキップ不可）
- Step 2: プラン策定（ユーザー許可必須）
- Step 3: 実装・コミット（`<type>(#<issue>): <short description>`）
- 根拠: `task.md:115-183`

### task フロー（Phase 2）
- ドラフト PR 作成（`templates/pr.md` 使用、`--body-file -` で本文渡し）
- 根拠: `task.md:187-204`

### task フロー（Phase 3）
- 最終報告（実装ファイル・テスト・issue URL・PR URL・次ステップ）
- 根拠: `task.md:207-223`

### ゲート
- G-1: `docs/.ai/repo.profile.json` の存在
- G-2: main ブランチかつワークスペースがクリーン（差分は stash で退避）
- 根拠: `task.md:23-32`

---

## 2. `patch.md` — 軽微修正フロー

### 概要
ドキュメント変更を伴わない軽微な修正専用。issue/PR 不要。
- 根拠: `patch.md:1-8`

### ワークフロー
1. ルーティング判定（docs 変更が必要なら `/task` へ誘導して終了）
2. branch 作成（`patch/<slug>`）
3. 変更・コミット（複数 OK、`patch: <説明>` 形式）
4. ユーザーに ff-merge 手順を通知して main に戻る
- 根拠: `patch.md:29-84`

### エスカレーション（→ task フロー）
実行中にドキュメント変更が必要と判明した場合:
1. 現時点の変更をコミット
2. `templates/issue.md` から issue を作成
3. `/task` Phase 1 Step 2（プラン策定）から継続
4. ブランチは `patch/<slug>` のまま再利用
- 根拠: `patch.md:95-112`

### ゲート
- G-1: `docs/.ai/repo.profile.json` の存在
- G-2: main ブランチにいること
- G-3: ワークスペースがクリーン（差分は stash で退避）
- 根拠: `patch.md:11-24`

---

## 3. `docs-sync.md` — ドキュメント同期フロー

### 概要
git diff を事実として docs および README.md を最小更新し、ドラフト PR を公開する。全体再構築は禁止。
- 根拠: `docs-sync.md:1-10`

### ワークフロー
1. `git diff --name-only` で変更ファイルを特定
2. PR 本文から `/docs-sync への引き継ぎ事項` を読み取る
3. 対象ファイルの targeted diff を取得し、docs 更新対象を確定
4. HARD STOP 判定（全体再構築が必要な場合は `/init-docs` を促して終了）
5. docs を最小更新
6. ドラフト PR を公開（`gh pr ready`）
- 根拠: `docs-sync.md:各フェーズ`

### HARD STOP 条件
以下のいずれかで `/init-docs` を要求して終了:
- (A) 新規主要レイヤ/トップレベル構造の追加疑い
- (B) 起動経路・エントリポイント変更の疑い
- (C) 10 ファイル以上かつ 3 ドメイン以上の広範な変更
- 根拠: `docs-sync.md:各 HARD STOP 節`

---

## 4. `init-docs.md` — ドキュメント初期化フロー

### 概要
リポジトリ実態の全体把握と設計ドキュメント再構築。重い初期化コマンド。
- 根拠: `init-docs.md:1-8`

### ワークフロー（5 フェーズ）
1. プロジェクト分析（ディレクトリ・技術スタック・エントリポイント・機能・依存）
2. `docs/.ai/repo.profile.json` 生成（事実のみ、補完禁止）
3. docs 生成（L1/L2/L3 + 追加 docs）
4. 整合性検証（docs↔実体、docs↔docs/.ai/repo.profile.json、CI 整合）
5. CLAUDE.md 更新
- 根拠: `init-docs.md:39-222`

### 再実行トリガー
- `/docs-sync` が HARD STOP を検知
- docs が現状を説明できなくなった
- 新規レイヤ導入・エントリポイント変更の疑い
- 根拠: `init-docs.md:9-19`

---

## 5. `templates/issue.md` — issue 本文テンプレート

使用コンテキスト:
- `task.md` Step 0（issue 自動生成時）
- `patch.md` エスカレーション時
- 根拠: `task.md:129`, `patch.md:103`

セクション: 概要・背景・作業スコープ・完了条件（+ エスカレーション時: /patch 実施済み変更・追加スコープ）

---

## 6. `templates/pr.md` — PR 本文テンプレート

使用コンテキスト: `task.md` Phase 2（ドラフト PR 作成時）
- 根拠: `task.md:197`

セクション: 実装サマリ・変更ファイルと内容・変更の種別・/docs-sync への引き継ぎ事項・留意点

---

## 未確認事項

- CI 定義: `.github/workflows/` が存在しない（CI なし）。確認済み。
- 実行ランタイム: このリポジトリ自体は Markdown のみ。実行ランタイムなし。確認済み。
- `docs-sync.md` の HARD STOP 条件 (C) の詳細: 「10 ファイル以上かつ 3 ドメイン以上」は `docs-sync.md` 内の定義に基づく。実際の適用は AI の判断に委ねられる。
