# /docs-sync

あなたはこのリポジトリの「ドキュメント同期」に特化した AI エージェントです。

- **実装ファイルへの変更は一切行わない**
- docs/* および README.md の最小更新のみを行う。ただし HARD STOP 復旧時は、包括的なドキュメント再構築を `/init-docs` の documentation-only mode へ委譲する
- **`docs/L0_concept/`（concept.md, policy.md）には一切書き込まない**。L0 相当の記述を検知した場合は `docs/.ai/l0_candidates.md` へ候補を追記するに留める（L0 への実際の追記はユーザー承認を経て `/concept-maker` が行う）
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

セッション temp ディレクトリを特定する（`hooks/lib/session-paths.sh` が `hooks/lib/session-id.sh` の `session_id_resolve` を再利用して1行で絶対パスを返す。brace expansion や代入への command substitution をコマンド自体に含めないことで worktree 隔離セッションでの harness 拒否を避ける、issue #316）:
- Claude Code: `bash ~/.claude/hooks/lib/session-paths.sh session-tmp-dir`
- Codex CLI: `bash ~/.codex/hooks/lib/session-paths.sh session-tmp-dir`

出力された1行の絶対パスを以降 `SESSION_TMP_DIR` として扱う。

- `${SESSION_TMP_DIR}/pr-body.md` が存在する場合:
    - 「/docs-sync への引き継ぎ事項」セクションが存在する場合のみ解析する
    - 設計意図・背景、git diff に現れない影響、注意箇所を読み取る
    - `Specific docs sections to update` フィールドに `docs/L3_implementation/specification_summary.md:<line-range>` 形式の citation が含まれる場合、その値を抽出し保持する（Phase 2 で再利用する）。ファイル名や説明文のみの場合は citation なしとして扱う
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
以下のいずれかに該当する場合、懸念を報告し、下記「HARD STOP からの自動復旧」を実行する:
- (A) 新しい主要レイヤ/トップレベル構造が追加された疑い
      判定基準: `apps/` `packages/` `infra/` `services/` 等がファイル一覧のトップに新出している
- (B) 起動経路・エントリポイントが変わった疑い
      判定基準: `src/main.*` `server.*` `app.*` `pages/` 等が追加または移動している
- (C) 変更が広範で「局所 docs 更新」の前提が崩れている
      判定基準: 変更ファイルが **10 件以上** かつ **3 領域以上** にまたがっている

##### HARD STOP からの自動復旧

1. HARD STOP の判定理由をユーザーへ報告する
2. `/init-docs` を **documentation-only mode** で自動実行する
    - 現在の作業ブランチを維持する
    - `/init-docs` Phase 1〜6 の包括的な再観測・ドキュメント再構築を実行する
    - `/init-docs` Phase 7 は実行しない（commit・push・PR 作成を行わない）
3. `/init-docs` が「完了」と判定して制御を返した場合:
    - 包括的なドキュメント再構築により Phase 2 および Phase 3 Step 1〜Step 2b は完了済みとして扱う
    - Phase 3 Step 3 へ進み、`/docs-sync` の責務として変更を commit し、結果を書き出す
    - 呼び出し元には通常の `/docs-sync` 完了として制御を返す。呼び出し元は `/init-docs` の実行有無を判定しない
4. `/init-docs` が「部分完了」と判定した、または失敗した場合:
    - commit・push・PR 作成を行わず、未確認事項またはエラーを報告して終了する

この復旧経路でも `/docs-sync` 自身は push・PR 作成を行わない。後続の `/git-pr` が通常どおり ready PR を作成する。

---

### Phase 2: 更新対象の特定（docs/* および README.md）

- 変更領域に対応する更新対象 docs を根拠付きで列挙する
- **ファイル名パターンによる決定論的ルール**: `.github/workflows/*` の追加・削除・変更を検出した場合は、解釈の余地なく `docs/L2_development/cicd.md` と `docs/L2_development/consistency_checks.md` を更新対象タスクへ追加する（プローズ判断のみに委ねない）。この更新は通常、workflow ファイルの内容をそのまま転記する「事実更新」（確認不要）に分類される
- 最小更新方針を確定する:
    - 事実更新（パス/設定値/コマンド/型/エンドポイント）
    - 手順更新（setup/run/test）
    - 仕様サマリ更新（specification_summary は該当箇所のみ。Phase 1 Step 2 で citation を取得済みの場合はその行範囲を `offset`/`limit` で対象読みし、読み取った内容が対象ファイル（`Specific docs sections to update` フィールドが言及するファイル）に対応する `###` 見出しを含んでいるか検証する。含んでいれば独自の再特定は行わない。含んでいない（citation の行範囲がずれている、または誤っている＝stale citation）場合、または citation がない場合は Glob/Grep 等で該当箇所を独自に特定する）
- **L0_concept の扱い**: `/docs-sync` では L0_concept（concept.md / policy.md）を一切更新しない
    - L0 は「意思決定の記録」であり、git diff から機械的に追従できる性質ではないため
    - L0 相当の記述を検知した場合の扱いは Phase 3 Step 2b（L0 昇格候補のキューイング）を参照。`/init-docs` へは促さない（`/init-docs` は L0 が存在しない場合の新規作成のみを行い、既存 L0 の更新経路ではない）
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
- **確認不要（既決の内容の文章化）**: git diff と、実装前にユーザーが承認した作業プランから内容が一意に定まる更新
    - 実装済みの振る舞いを仕様サマリの説明文（プローズ）として要約する場合
    - 承認済みプランに含まれる設計意図・背景を、git diff と矛盾しない範囲で docs に反映する場合
- **確認必要（未解決の判断）**: git diff と承認済みプランを読んでも、文書化の意味・範囲に複数の妥当な選択肢が残る更新
    - `pr-body.md` の補助情報に、承認済みプランでは確定していない設計意図・背景があり、どの解釈を docs に採用するかを決める必要がある場合
    - 更新対象 docs の特定や根拠付けに、文書化の範囲を変えうる複数の解釈がありうる場合

分類に迷う場合は「確認必要」側に倒す。

判定後の扱い:
- 全項目が「確認不要」の場合: 許可を求めずそのまま Phase 3 へ進む
- 1項目でも「確認必要」に該当する場合:
    - 実装済みの挙動や承認済みプランを言い換えるだけの確認は行わない。該当項目について、反映する文章そのものではなく、未解決の選択肢と採用候補の根拠となった解釈・理解を提示する
    - 「この解釈で合っているか」だけをユーザーに確認する
    - 確認が取れたら、その解釈に基づいて Phase 3 で実際の文章化を行う（文章そのものの再確認は求めない）
    - 「確認不要」項目はこの場で提示せず、Phase 3 でそのまま更新する

##### HARD STOP（/init-docs が必要）:
- (A) 根拠が辿れず、更新対象 docs を特定できない
- (B) citation の検証に失敗した（stale citation）、または citation がなく、かつ独自探索でも specification_summary.md の「該当箇所」が特定できない（全体書換えしか手がない状態）

該当した場合は Phase 1 Step 4 の「HARD STOP からの自動復旧」と同じ手順を実行する。

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

#### Step 2b: L0 昇格候補の検知（L0 ファイル自体は変更しない）

Step 2 で変更履歴を更新した各 L3 doc について、`git diff main...HEAD -- <L3 docのパス>` でこの PR による追加分を確認し、「重要な設計判断」セクションに追加された記述が `docs/L0_concept/policy.md` の既存カテゴリ（技術選定ポリシー・セキュリティ方針・運用/性能方針・禁止事項・整合性方針）に類する project-wide な決定と読めるかを判断する。

該当する場合:
- `docs/.ai/l0_candidates.md` が存在しない場合は新規作成する（ヘッダーのみの空ファイルは事前生成しない。最初の候補追加時に作成する）
- 1 候補につき1行で追記する: `- <L3 docのパス>:<行範囲> — <一行要約> (issue #<関連issue番号>)`
- **`docs/L0_concept/concept.md`・`policy.md` には一切書き込まない。** このステップの唯一の出力はキューへの追記であり、L0 への昇格判断・追記は `/concept-maker` がユーザー承認を経て行う

該当しない場合、または L3 doc の変更履歴更新自体が発生しなかった場合はこのステップをスキップする。この判定はキューへの追記のみが結果であり L0 を直接変更しないため、Phase 2 の「確認不要/確認必要」分類の対象外（常に確認不要相当）として扱う。

#### Step 3: コミットと結果書き出し

**docs 変更があった場合:**
- `/git-commit` を実行する（パラメータ: `fixed_message="docs: sync documentation"`）

**セッション temp への書き出し（常に実行）:**

セッション temp ディレクトリを特定する（Step 2 で取得済みの場合は再利用。`hooks/lib/session-paths.sh` が `hooks/lib/session-id.sh` の `session_id_resolve` を再利用して1行で絶対パスを返す。issue #316）:
- Claude Code: `bash ~/.claude/hooks/lib/session-paths.sh session-tmp-dir`
- Codex CLI: `bash ~/.codex/hooks/lib/session-paths.sh session-tmp-dir`

出力された1行の絶対パスを以降 `SESSION_TMP_DIR` として扱う。

`${SESSION_TMP_DIR}` が特定できた場合: `${SESSION_TMP_DIR}/pr-docs-sync-result.md` を書き出す:

```
## Docs Sync Result
- Updated files: [list、または "none"]
- Basis: git diff main...HEAD adopted as fact, pr-body.md referenced as supplement
- HARD STOP: none、または resolved by /init-docs documentation-only mode
```

---

### Phase 4: 最終報告

A. 更新した docs ファイル一覧と更新内容サマリ（更新なしの場合はその旨）
B. `docs/.ai/l0_candidates.md` が存在し中身が空でない場合: 「N件の L0 昇格候補があります。`/concept-maker` を実行してください」と案内する（`/concept-maker` をこのフローから自動実行しない）
C. 次のステップ: `/git-pr` が自動実行される（または手動で `/git-pr` を実行する）

---

## 注意事項
- git diff を「事実」、`pr-body.md` を「補助」として扱う。矛盾時は git diff を優先する
- HARD STOP 時は /init-docs の documentation-only mode を自動実行し、完了後は Phase 3 Step 3 へ合流して呼び出し元へ通常完了として制御を返す
- push・PR 作成は行わない（`/git-pr` が担う）
