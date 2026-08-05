# /docs-sync specification

## 目的・役割

`commands/docs-sync.md` は PR ブランチ上で `git diff main...HEAD` を事実として docs と README.md を最小更新し、L3 per-file doc の変更履歴セクションを自動更新するドキュメント同期専用コマンドである。

`/task` から自動呼び出しされるほか、ユーザーが手動で呼び出すこともある。実装ファイルへの変更は一切行わない。`docs/L0_concept/`（concept.md, policy.md）にも一切書き込まない（issue #273）。

根拠: `commands/docs-sync.md:1-11`

## 動作の概要

4 フェーズで構成される:

```
Phase 1: 変更の把握（git diff --name-only + pr-body.md）
Phase 2: 更新対象の特定（docs/* および README.md）
Phase 3: docs・README.md 最小更新 + L3 変更履歴更新 + L0 昇格候補キューイング + 結果書き出し
Phase 4: 最終報告（L0 候補ありの案内を含む）
```

根拠: `commands/docs-sync.md:1-11`, `commands/docs-sync.md:30-139`

## 主要なフロー

### 実行前提ゲート

- G-1: `docs/.ai/repo.profile.json` の存在確認
- G-2: `docs/` の存在確認
- G-3: main ブランチ以外にいること

根拠: `commands/docs-sync.md:13-20`

### Phase 1: 変更の把握

`git diff main...HEAD --name-only` でファイル一覧のみ取得し（全量 diff は取得しない）、セッション temp の `pr-body.md` から引き継ぎ事項を解析する。ファイルが存在しない場合は補助情報なしとして git diff のみで判断する。矛盾時は git diff を優先する。

根拠: `commands/docs-sync.md:37-71`

### Phase 2: 更新対象の特定

変更領域に対応する更新対象 docs を根拠付きで列挙する。`.github/workflows/*` の追加・削除・変更を検出した場合は、プローズ判断に頼らず `docs/L2_development/cicd.md` と `docs/L2_development/consistency_checks.md` を無条件で更新対象タスクへ追加する決定論的ルールを持つ（issue #271。以前はプローズ判断のみに委ねていたため、`.github/workflows/shellcheck.yml` 追加時にこの2ファイルの更新漏れが発生していた）。HARD STOP 判定はファイル名パターンで行う（10件以上かつ3領域以上、主要レイヤ新出、エントリポイント変更）。L0_concept は更新しない。

タスクリストの各項目を「確認不要（git diff の値をそのまま転記するだけ）」と「確認必要（文脈・意図を解釈して文章化する）」に分類する（issue #229）。全項目が確認不要なら許可を求めずそのまま Phase 3 へ進む。1項目でも確認必要な場合は、その項目について反映する文章そのものではなく根拠となった解釈を提示し、「解釈が合っているか」だけを確認する。文章化自体は確認後の Phase 3 で行い、再確認は求めない。分類に迷う場合は確認必要側に倒す。

根拠: `commands/docs-sync.md:81-137`

### Phase 3: docs・README.md 最小更新 + L3 変更履歴更新 + L0 昇格候補キューイング

4 つのステップで構成される:

**Step 1**: docs/* および README.md の最小更新（作業プランに従い、プラン外の変更は禁止）

**Step 2**: L3 per-file doc の変更履歴セクション更新
- Phase 1 で取得したファイル一覧から `docs/` 配下を除くソースファイルを対象とする
- 各ファイルに対応する `docs/L3_implementation/<path>.md` が存在する場合のみ処理する
- `git log --oneline -10 -- <file>` を実行し、`## 変更履歴（git log より自動生成）` セクションを更新または末尾に追加する
- L3 doc が存在しないファイルはスキップ（L3 doc 新規作成は `/task` が担う）
- `docs/` 配下のファイル（`docs/L3_implementation/` を含む）は対象外

**Step 2b**: L0 昇格候補の検知（`docs/L0_concept/` 自体は変更しない）
- Step 2 で変更履歴を更新した各 L3 doc について、この PR による「重要な設計判断」への追加分を `git diff main...HEAD -- <L3 docのパス>` で確認する
- `docs/L0_concept/policy.md` の既存カテゴリ（技術選定・セキュリティ・運用/性能・禁止事項・整合性）に類する project-wide な決定と読める場合、`docs/.ai/l0_candidates.md`（存在しなければ新規作成）へ `- <L3 docのパス>:<行範囲> — <一行要約> (issue #<N>)` の形式で1行追記する
- L0 ファイル自体（`concept.md`・`policy.md`）には一切書き込まない。判断はキューイングのみに使われるため、Phase 2 の「確認不要/確認必要」分類の対象外として扱う

**Step 3**: docs 変更があった場合のみ `/git-commit`（`fixed_message="docs: sync documentation"`）を実行し、`SESSION_TMP_DIR/pr-docs-sync-result.md` を書き出す（docs 変更の有無にかかわらず常に実行）。push は行わない。

Phase 4 最終報告では、`docs/.ai/l0_candidates.md` が空でない場合に `/concept-maker` の実行をユーザーへ案内する（自動実行はしない）。

根拠: `commands/docs-sync.md:140-203`, `commands/docs-sync.md:206-209`, issue #273

## 重要な設計判断

### git diff を事実とし pr-body.md を補助とする理由

`pr-body.md` は主観的な説明を含む可能性があるが、git diff は変更の実態そのものである。矛盾が生じた場合に git diff を優先することで、docs が実装と乖離するリスクを防ぐ。

### L3 変更履歴の更新を docs-sync が担う理由

`/task` が L3 doc を作成するタイミングでは `/git-commit` がまだ実行されていないため、最新コミットが `git log` に含まれない。docs-sync はコミット後に実行されるため、当該コミットを含む正確な履歴を記録できる。

また docs-sync は `git diff --name-only` で修正ファイルの全量を把握しており、L3 doc の存在確認と git log 実行を機械的に行える。

### HARD STOP（/init-docs が必要なケース）

以下の場合は docs-sync の前提（局所更新）が崩れているため処理を止める:
- 新しい主要レイヤ/トップレベル構造の追加疑い
- 起動経路・エントリポイントの変更疑い
- 変更ファイルが 10 件以上かつ 3 領域以上

根拠: `commands/docs-sync.md:71-78`, `commands/docs-sync.md:134-136`

## 統合ポイント

- 呼び出し元: `commands/task.md`（Phase 2 Step 1 から自動呼び出し）、ユーザーの手動呼び出し
- 呼び出すもの: `/git-commit`（`fixed_message="docs: sync documentation"`）
- 書き出す temp ファイル: `SESSION_TMP_DIR/pr-docs-sync-result.md`（`/git-pr` が参照する）
- 依存: `docs/.ai/repo.profile.json`、PR ブランチ

## 注意事項

- `docs/L3_implementation/` 配下のファイルは Phase 3 Step 2 の L3 変更履歴更新の対象外（自己参照ループを防ぐ）
- push・PR 作成は行わない（`/git-pr` が担う）
- HARD STOP 時は `/init-docs` を実行してから `/task → /docs-sync` をやり直す
- セッション temp ディレクトリの特定（Phase 1 Step 2、Phase 3 Step 3）は `${STATE_ROOT}/current-session-approved-path`（共有ポインタファイル）を経由せず、`$CLAUDE_CODE_SESSION_ID` から直接導出する（issue #210。複数セッション同時実行時の混線を防ぐため）

## 変更履歴（git log より自動生成）

- e6845d7 feat(#273): introduce L0 promotion queue and /concept-maker; make L0 write-once by /init-docs
- 5722f08 feat(#271): add deterministic docs-sync CI rule, wire approval hook tests into CI, dedupe work.md investigation text
- 4b3c0e1 feat(#229): make /docs-sync Phase 2 skip confirmation for mechanical updates, focus on interpretation
- db6d6c3 fix(#210): resolve session id from env instead of a shared pointer file
- 82717a1 feat(#167): add /git-pr command; refactor push and PR creation out of /task and /docs-sync
- 5c9d8f2 feat(#165): extend docs-sync to auto-insert git log into L3 per-file docs
- 89d5fad feat(#157): move git-commit to commands/, add skill wrapper, update all callers to /git-commit
- f6288ac feat(#98): add git push to /docs-sync Phase 3
- e07fe3b fix: enforce independent README.md check in docs-sync Phase 2
- f0d7bc1 feat(#41): move templates/ to repo root, add partials/ symlink, clean up stale symlinks
