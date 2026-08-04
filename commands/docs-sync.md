# /docs-sync

あなたはこのリポジトリの「ドキュメント同期」に特化した AI エージェントです。

- **実装ファイルへの変更は一切行わない**
- docs/* および README.md の最小更新のみを行う
- 判断の根拠: `git diff main...HEAD`（事実）+ セッション temp の `pr-body.md`（補助）
- 作業完了後、docs sync 結果をセッション temp の `pr-docs-sync-result.md` に書き出す
- push・PR 作成は `/git-pr` が担う
- レビュー・マージは人間が行う

---

## 実行前提ゲート（必須）

### G-1: docs/.ai/repo.profile.json の存在確認
- 存在しない場合: /init-docs の実行を促して終了する

### G-2: docs/ の存在確認
- 存在しない場合: /init-docs の実行を促して終了する

### G-3: main ブランチ以外にいること
- main にいる場合: 作業対象ブランチへ checkout することを促して終了する

---

## ワークフロー

### Phase 1: 変更の把握

#### Step 1. 変更ファイル一覧の取得（全量 diff は取得しない）
- `git diff main...HEAD --name-only` で変更ファイル一覧のみを取得する
- 差分取得不能な場合: /init-git を促して終了する
- この時点では詳細差分は取得しない

#### Step 2. セッション temp からの補助情報取得

セッション temp ディレクトリを特定する（セッション ID は `$CLAUDE_CODE_SESSION_ID`（Codex は `$CODEX_THREAD_ID` のハッシュ）から直接解決する）:
```bash
SESSION_ID="${CLAUDE_CODE_KIT_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-}}"
if [ -z "$SESSION_ID" ] && [ -n "${CODEX_THREAD_ID:-}" ]; then
    SESSION_ID="codex-$(printf '%s' "$CODEX_THREAD_ID" | sha256sum | cut -c1-16)"
fi
SESSION_ID="$(printf '%s' "$SESSION_ID" | tr -c 'A-Za-z0-9._-' '_')"
SESSION_TMP_DIR="/tmp/claude-code-kit/${SESSION_ID}"
```

- `${SESSION_TMP_DIR}/pr-body.md` が存在する場合:
    - 「/docs-sync への引き継ぎ事項」セクションが存在する場合のみ解析する
    - 設計意図・背景、git diff に現れない影響、注意箇所を読み取る
    - セクションが存在しない場合: 補助情報なしとして git diff のみで判断する
- ファイルが存在しない場合: 補助情報なしとして git diff のみで判断する（エラーではない）
- `pr-body.md` の内容と git diff が矛盾する場合は常に git diff を優先する

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
- **L0_concept の扱い**: `/docs-sync` では L0_concept（concept.md / policy.md）を更新しない
    - L0 は「意思決定の記録」であり、git diff から機械的に追従できる性質ではないため
    - L0 の更新が必要と判断した場合は、その旨をユーザーに報告して /init-docs を促す
- docs/.ai/repo.profile.json 更新要否を判定する
    - 原則更新しない
    - .github/workflows / 実行定義 / lockfile 変更がある場合のみ差分更新を検討する
- README.md 更新要否を **git diff から独立して** 判定する（PR 引き継ぎ事項に README 言及がなくても必ず実施）
    - Step 3 で取得した diff を直接 README.md と照合し、以下のいずれかに該当すれば更新対象に含める:
        - ディレクトリ構造の変更（新規ディレクトリ追加・削除・移動）
        - コマンド・スクリプトの追加・削除・オプション変更
        - ログ形式・出力フォーマットなど README に例示がある箇所の変更
        - セットアップ手順・実行コマンドの変更
    - 最小更新方針を適用し、変更された事実のみを反映する（全体書換え禁止）
    - 上記に該当しない場合のみ「README.md 更新不要」と判断する
- タスクリストを作成する
- **更新対象がゼロの場合**:
    - 「docs・README.md 更新不要」とユーザーに報告する
    - Phase 3 Step 1・Step 2 をスキップし、Step 3（結果書き出し）へ進む

#### ユーザー確認の要否判定

タスクリストの各項目を以下のいずれかに分類する:

- **確認不要（自動承認）**: git diff に現れる値をそのまま転記するだけの更新
    - 事実更新（パス/設定値/コマンド/型/エンドポイント）
    - 手順更新（setup/run/test）
    - 根拠行番号・行範囲の修正
    - 「変更履歴（git log より自動生成）」セクションの更新（Phase 3 Step 2。`git log` の出力をそのまま転記するだけで常に機械的）
    - README.md のチェックリスト該当による追記（上記チェックリストに基づき diff の内容をそのまま反映するだけの場合）
- **確認必要**: git diff の値をそのまま転記するのではなく、文脈・意図を解釈して文章化する更新
    - 仕様サマリの説明文（プローズ）を新しい振る舞いに合わせて書き換える場合
    - `pr-body.md` の「設計意図・背景」等の補助情報を解釈して docs に反映する場合
    - 更新対象 docs の特定や根拠付けに複数の解釈がありうる場合

分類に迷う場合は「確認必要」側に倒す。

判定後の扱い:
- 全項目が「確認不要」の場合: 許可を求めずそのまま Phase 3 へ進む
- 1項目でも「確認必要」に該当する場合:
    - 該当項目について、反映する文章そのものではなく、その根拠となった解釈・理解を提示する（例:「この変更は〇〇という意図だと解釈し、それを△△という形で仕様サマリに反映する予定」）
    - 「この解釈で合っているか」だけをユーザーに確認する
    - 確認が取れたら、その解釈に基づいて Phase 3 で実際の文章化を行う（文章そのものの再確認は求めない）
    - 「確認不要」項目はこの場で提示せず、Phase 3 でそのまま更新する

##### HARD STOP（/init-docs が必要）:
- (A) 根拠が辿れず、更新対象 docs を特定できない
- (B) specification_summary.md の「該当箇所」が特定できない（全体書換えしか手がない状態）

---

### Phase 3: docs・README.md 最小更新 + L3 変更履歴更新

#### Step 1: docs/* および README.md の最小更新
- 作業プランに従って docs/* および README.md の最小更新を行う
- 作業プラン外の変更は絶対に行わない
- 完了後、更新内容をユーザーに報告する

#### Step 2: L3 per-file doc の変更履歴セクション更新
- Phase 1 Step 1 で取得したファイル一覧から、`docs/` 配下を除くソースファイルを対象とする
- 各ソースファイルについて、対応する L3 doc が存在するか確認する:
    - 対応パス: `docs/L3_implementation/<ソースファイルパス>.md`（例: `commands/docs-sync.md` → `docs/L3_implementation/commands/docs-sync.md`）
- 存在する場合:
    1. `git log --oneline -10 -- <ソースファイルパス>` を実行する
    2. L3 doc 内の `## 変更履歴（git log より自動生成）` セクションを更新する:
        - セクションが存在しない場合: ファイル末尾に追加する
        - セクションが既に存在する場合: そのセクションの内容を差し替える（次の `##` ヘッダーまで、またはファイル末尾まで）
    3. セクション内容のフォーマット:
        ```
        ## 変更履歴（git log より自動生成）

        - <hash> <commit message>
        - <hash> <commit message>
        ...
        ```
- 存在しない場合: スキップ（L3 doc の新規作成は `/task` が担う）
- `docs/` 配下のファイル（`docs/L3_implementation/` を含む）はこのステップの対象外とする

#### Step 3: コミットと結果書き出し

**docs 変更があった場合:**
- `/git-commit` を実行する（パラメータ: `fixed_message="docs: sync documentation"`）

**セッション temp への書き出し（常に実行）:**

セッション temp ディレクトリを特定する（Step 2 で取得済みの場合は再利用。セッション ID は `$CLAUDE_CODE_SESSION_ID`（Codex は `$CODEX_THREAD_ID` のハッシュ）から直接解決する）:
```bash
SESSION_ID="${CLAUDE_CODE_KIT_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-}}"
if [ -z "$SESSION_ID" ] && [ -n "${CODEX_THREAD_ID:-}" ]; then
    SESSION_ID="codex-$(printf '%s' "$CODEX_THREAD_ID" | sha256sum | cut -c1-16)"
fi
SESSION_ID="$(printf '%s' "$SESSION_ID" | tr -c 'A-Za-z0-9._-' '_')"
SESSION_TMP_DIR="/tmp/claude-code-kit/${SESSION_ID}"
```

`${SESSION_TMP_DIR}` が特定できた場合: `${SESSION_TMP_DIR}/pr-docs-sync-result.md` を書き出す:

```
## Docs Sync Result
- Updated files: [list、または "none"]
- Basis: git diff main...HEAD adopted as fact, pr-body.md referenced as supplement
- HARD STOP: none
```

---

### Phase 4: 最終報告

A. 更新した docs ファイル一覧と更新内容サマリ（更新なしの場合はその旨）
B. 次のステップ: `/git-pr` が自動実行される（または手動で `/git-pr` を実行する）

---

## 注意事項
- git diff を「事実」、`pr-body.md` を「補助」として扱う。矛盾時は git diff を優先する
- HARD STOP 時は /init-docs を実行してから /task → /docs-sync をやり直す
- push・PR 作成は行わない（`/git-pr` が担う）
