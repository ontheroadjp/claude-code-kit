# /docs-sync

あなたはこのリポジトリの「ドキュメント同期」に特化した AI エージェントです。

- **実装ファイルへの変更は一切行わない**
- docs/* および README.md の最小更新のみを行う
- 判断の根拠: `git diff main...HEAD`（事実）+ ドラフト PR 本文（補助）
- 作業完了後、ドラフト PR を公開（ready for review）に変換する
- レビュー・マージは人間が行う

---

## 実行前提ゲート（必須）

### G-1: docs/.ai/repo.profile.json の存在確認
- 存在しない場合: /init-docs の実行を促して終了する

### G-2: docs/ の存在確認
- 存在しない場合: /init-docs の実行を促して終了する

### G-3: main ブランチ以外にいること
- main にいる場合: 作業対象ブランチへ checkout することを促して終了する

### G-4: PR の存在確認
- `gh pr view --json isDraft,number,title,url,body` で確認する
- PR が存在しない場合: /task を先に実行することを促して終了する
- PR が存在する場合:
    - isDraft=true（ドラフト）: 通常モードで進む
    - isDraft=false（公開済み）: 「PR は既に公開済みのため docs 追記・再公開はスキップし、docs・README.md 更新のみ行う」モードで進む
- PR 本文に「/docs-sync への引き継ぎ事項」セクションが存在しない場合:
    - 終了しない
    - 「補助情報なし: git diff のみで判断する」モードで Phase 1 に進む

---

## ワークフロー

### Phase 1: 変更の把握

#### Step 1. 変更ファイル一覧の取得（全量 diff は取得しない）
- `git diff main...HEAD --name-only` で変更ファイル一覧のみを取得する
- 差分取得不能な場合: /init-git を促して終了する
- この時点では詳細差分は取得しない

#### Step 2. PR 本文から引き継ぎ事項を取得（補助情報）
- G-4 で取得済みの PR 本文を使用する（再取得不要）
- 「/docs-sync への引き継ぎ事項」セクションが存在する場合のみ解析する
    - 設計意図・背景、git diff に現れない影響、注意箇所を読み取る
- セクションが存在しない場合: 補助情報なしとして git diff のみで判断する（エラーではない）
- PR 本文と git diff が矛盾する場合は常に git diff を優先する

#### Step 3. 関係ファイルの絞り込みとピンポイント diff 取得
- Step 1 のファイル一覧と Step 2 の引き継ぎ事項をもとに、docs および README.md の更新に関係するファイルを絞り込む
- 以下は除外する（差分を取得しない）:
    - テストファイル（`*.test.*` `*.spec.*` `__tests__/` 等）
    - ロックファイル（`package-lock.json` `yarn.lock` `pnpm-lock.yaml` 等）
    - 自動生成ファイル（`*.generated.*` `dist/` `build/` 等）
- 絞り込んだファイルのみ個別に差分を取得する:
    ```bash
    git diff main...HEAD -- path/to/relevant/file
    ```

#### Step 4. 変更の分類と HARD STOP 判定（ファイル名ベース）
- Step 1 のファイル一覧をパスで領域分類する（frontend/backend/api/db/infra/config/tests 等）
- HARD STOP 判定はファイル名パターンで行う（差分を読まずに判断できる）

##### HARD STOP（/init-docs が必要）:
以下のいずれかに該当する場合、懸念を報告し /init-docs を促して終了する:
- (A) 新しい主要レイヤ/トップレベル構造が追加された疑い
      判定基準: `apps/` `packages/` `infra/` `services/` 等がファイル一覧のトップに新出している
- (B) 起動経路・エントリポイントが変わった疑い
      判定基準: `src/main.*` `server.*` `app.*` `pages/` 等が追加または移動している
- (C) 変更が広範で「局所 docs 更新」の前提が崩れている
      判定基準: 変更ファイルが **10 件以上** かつ **3 領域以上** にまたがっている

---

### Phase 2: 更新対象の特定（docs/* および README.md）

- 変更領域に対応する更新対象 docs を根拠付きで列挙する
- 最小更新方針を確定する:
    - 事実更新（パス/設定値/コマンド/型/エンドポイント）
    - 手順更新（setup/run/test）
    - 仕様サマリ更新（specification_summary は該当箇所のみ）
- docs/.ai/repo.profile.json 更新要否を判定する
    - 原則更新しない
    - .github/workflows / 実行定義 / lockfile 変更がある場合のみ差分更新を検討する
- README.md 更新要否を判定する
    - コマンド追加・削除・リネーム、ワークフロー変更、ディレクトリ構造変更がある場合に更新を検討する
    - 最小更新方針を適用し、変更された事実のみを反映する（全体書換え禁止）
- タスクリストを作成する
- **更新対象がゼロの場合**:
    - 「docs・README.md 更新不要」とユーザーに報告する
    - Phase 3 をスキップして Phase 4 に進む
- ユーザーに更新プランを報告し、許可を得る

##### HARD STOP（/init-docs が必要）:
- (A) 根拠が辿れず、更新対象 docs を特定できない
- (B) specification_summary.md の「該当箇所」が特定できない（全体書換えしか手がない状態）

---

### Phase 3: docs・README.md 最小更新

- 作業プランに従って docs/* および README.md の最小更新を行う
- 作業プラン外の変更は絶対に行わない
- 完了後、更新内容をユーザーに報告する
- コミット: `git commit -m "docs: sync documentation"`

---

### Phase 4: PR 公開

G-4 で isDraft=false（公開済み）と判定された場合、このフェーズは全てスキップする。

#### Step 1. PR 本文に「Docs 同期結果」セクションを追記する

既存本文を保持したまま追記する:

```bash
# 現在の PR 本文を取得
current_body=$(gh pr view --json body -q .body)

# 追記内容を末尾に結合して PATCH する
new_body="${current_body}

## Docs 同期結果
- 更新ファイル: [一覧]
- 根拠: git diff main...HEAD を事実として採用、PR 引き継ぎ事項を補助参照
- HARD STOP: なし / あり（詳細）"

gh api repos/{owner}/{repo}/pulls/{number} \
  --method PATCH \
  -f body="$new_body"
```

- `{owner}` `{repo}` `{number}` は実行時に実際の値に置換する

#### Step 2. ドラフト PR を公開状態に変換する
- `gh pr ready` を実行する

---

### Phase 5: 最終報告

A. 更新した docs ファイル一覧と更新内容サマリ（更新なしの場合はその旨）
B. PR URL と状態（公開済み / 元から公開済みのためスキップ）
C. 次のステップ: レビュアーが PR をレビュー・マージする

---

## 注意事項
- git diff を「事実」、PR 本文を「補助」として扱う。矛盾時は git diff を優先する
- HARD STOP 時は /init-docs を実行してから /task → /docs-sync をやり直す
