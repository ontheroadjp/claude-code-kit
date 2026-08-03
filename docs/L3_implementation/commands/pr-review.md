# /pr-review specification

## 目的・役割

`commands/pr-review.md` は、ready PR を実装元とは別の AI agent でレビューし、妥当な blocking finding を承認済みスコープ内で修正・再レビューして、最新 HEAD を `APPROVED` または `CHANGES_REQUESTED` に更新する。

責務は review 済み PR の作成までであり、merge、branch 削除、main checkout、main pull は人間の管理下に残す。

根拠: `commands/pr-review.md:1-15`, `commands/pr-review.md:189-197`

## 動作の概要

```
引数・実装 agent 判定
  → PR/workspace gate
  → 別 GitHub reviewer identity の確認
  → 各ラウンドで最新 base を取得
  → 最新 HEAD SHA を固定
  → round 1 はPR全体diff、round 2+は前ラウンドレビュー済みSHAからの増分diffを生成
  → 前ラウンドが trivial round なら confirm-only モード、それ以外は通常モードで opposite agent が read-only review
  → GitHub に APPROVED / CHANGES_REQUESTED を投稿
  → blocking finding があれば元 agent が検証・修正し、修正が全て trivial なら次ラウンド向けに trivial flag を残す
  → 最大3ラウンド再レビュー
  → APPROVED / CHANGES_REQUESTED / FAILED で終了
```

根拠: `commands/pr-review.md:18-34`, `commands/pr-review.md:82-217`

## 主要な判定ロジック

### opposite-agent routing

`CODEX_THREAD_ID` または `CODEX_CI` がある場合は Codex を実装元、Claude を reviewer とする。それ以外は Claude を実装元、Codex を reviewer とする。環境判定ができない場合は現在の agent を明示的に実装元として確定し、同じ agent に自己レビューさせない。

根拠: `commands/pr-review.md:17-33`

### reviewer identity

GitHub review 投稿には `AI_REVIEW_TOKEN` を優先し、既存 `CODEX_REVIEW_TOKEN` を fallback として使う。token の login が PR author と一致する場合は停止する。token 値は表示・保存しない。

根拠: `commands/pr-review.md:51-64`

### review と HEAD SHA の結合

各ラウンド開始時に `origin/<baseRefName>` を fetch してから GitHub の `headRefOid` と local HEAD を一致させ、その SHA を reviewer 出力の `REVIEWED_HEAD_SHA` に要求する。base fetch に失敗した場合は stale な diff を生成・投稿せず `FAILED` で終了する。review 投稿直前と投稿後にも SHA を照合し、approval の `commit_id` と現在の PR HEAD が一致する場合だけ `APPROVED` とする。

この base refresh と多段照合により、複数ラウンド中の base 更新を diff に反映し、review 中や投稿直前に追加 push があった場合も古い結果を最新 HEAD の approval として扱わない。

根拠: `commands/pr-review.md:82-114`, `commands/pr-review.md:156-174`

### インクリメンタルレビュー（round 2+ のスコープ縮小）

round 1 は `origin/<baseRefName>...HEAD` の全体 diff を reviewer に渡す。round 2 以降は直前ラウンドの `REVIEWED_HEAD_SHA`（`PREV_REVIEWED_SHA`）から現在 HEAD までの増分 diff（`round-${ROUND}-incremental.diff`）と直前ラウンドの `FINDINGS` を渡し、reviewer が承認済み範囲を毎回読み直さずに済むようにする。`PREV_REVIEWED_SHA` を前ラウンド出力から取得できない場合は全体 diff の通常モードにフォールバックする（fail-safe）。

根拠: `commands/pr-review.md:82-113`

### trivial round と confirm-only モード

Step 4.5 の修正適用後、修正が session-approved 内のみ・finding 1件あたりの diff 行数が `TRIVIAL_FIX_MAX_LINES=5` 以下・機械的な修正（typo・コメント・文言・単純な値修正等）のみを満たす場合、そのラウンドを trivial round として `round-${ROUND}-trivial.flag` に記録する。次ラウンドの reviewer 起動（Step 4.2）はこのフラグを見て、増分 diff と直前 findings の解消確認だけに絞った confirm-only モードのプロンプトを使う。confirm-only モードでも別 agent の起動・read-only 制約・機械判定契約は変更せず、APPROVE の可否は必ずこのラウンドの別 agent 起動結果に基づく（reviewer 起動自体を省略しない）。

根拠: `commands/pr-review.md:125-129`, `commands/pr-review.md:203-206`

### bounded remediation

review は `MAX_REVIEW_ROUNDS=3` に制限する。元 agent は finding の妥当性をコードと docs から再検証し、session-approved 内だけを修正する。最終ラウンドの変更要求、スコープ拡大、破壊的操作、秘密情報、権限追加が必要な finding は自動修正せず `CHANGES_REQUESTED` で人間へ返す。

根拠: `commands/pr-review.md:11-16`, `commands/pr-review.md:187-207`

## 重要な設計判断

### base branch を各ラウンドで更新する理由

base branch は初回 gate 後にも進む可能性がある。各ラウンドの diff 生成直前に base を fetch することで、そのラウンドの reviewer に最新の比較対象を渡す。fetch 失敗時は以前の remote-tracking ref を使わず fail closed とし、stale な context に基づく review 投稿を防ぐ。

根拠: `commands/pr-review.md:84-90`

### インクリメンタルレビュー・confirm-only モードを導入した理由

各ラウンドで reviewer subprocess をコールドスタートし、PR 全体 diff をゼロから読み直す設計は round 数に比例して遅くなる。round 1 は依然として全体をレビューする必要があるが、round 2 以降は「直前ラウンドで指摘された finding が解消されたか」「新たな blocking finding がその増分に含まれるか」を確認できれば十分なケースが多い。増分 diff と直前 findings だけを渡すことで reviewer が読む範囲を絞り、trivial な修正が続く場合はさらにプロンプト自体を confirm-only に絞ってレビュー負荷を減らす。ただし APPROVED の最終判定を出す reviewer 起動そのものは省略しない — 「別 agent による客観レビュー」という設計原則を壊さないため。`PREV_REVIEWED_SHA` が取得できない場合は全体 diff にフォールバックし、fail-safe を優先する。

根拠: `commands/pr-review.md:82-129`, `commands/pr-review.md:203-206`

### reviewer subprocess を read-only にする理由

別 agent は独立した批評者であり、実装者ではない。Codex は汎用の `codex exec` を `--sandbox read-only --ephemeral` で実行し、Claude は `Read` tool のみに制限する。修正・GitHub 投稿は元 agent が担当するため、reviewer が承認済みスコープや session approval を迂回して変更する経路を作らない。

Codex の専用 review subcommand は固定の finding 形式を出力するため使用しない。汎用 exec に機械可読契約を明示し、`--output-last-message` で最終回答だけを保存することで、進行イベントを混ぜずに `VERDICT`、`REVIEWED_HEAD_SHA`、`FINDINGS` を検証できる。

根拠: `commands/pr-review.md:131-154`

### merge を行わない理由

AI に review と修正の反復を任せつつ、main への統合は人間の明示操作として残すためである。review が失敗または収束しない場合も PR を保持し、現在状態から人間が判断できる。

根拠: `commands/pr-review.md:3-7`, `commands/pr-review.md:209-217`

## 統合ポイント

- 自動呼び出し元: `commands/git-pr.md` Step 8
- 手動呼び出し: `/pr-review #<PR番号>`
- reviewer CLI: `codex exec --sandbox read-only --ephemeral` または `claude -p`
- commit/docs: `/git-commit`、必要な場合は `/docs-sync`
- GitHub: `gh pr view`、`gh pr review`、`gh api user`
- 一時ファイル: `/tmp/claude-code-kit/<session-id>/pr-review-<PR番号>/`（各ラウンドの diff・増分 diff・review 出力・trivial flag を含む）

## 注意事項・既知の制限

- reviewer 投稿には PR author と異なる GitHub account の token が必要
- 自動修正は現在の session-approved に登録済みのファイルとツールに限定される
- Codex reviewer の機械判定には `--output-last-message` が保存した最終回答だけを使用する
- 各ラウンドの base fetch が失敗した場合は review context を生成・投稿せず `FAILED` で終了する
- review 出力が所定形式でない場合は GitHub review を投稿せず `FAILED` で終了する
- PR merge、close、branch 削除、main 同期は行わない
- 3ラウンドで収束しない finding は人間判断へ返す
- round 2+ の増分レビューは `PREV_REVIEWED_SHA` が前ラウンド出力から取得できることに依存する。取得できない場合は全体 diff にフォールバックする
- confirm-only モードは reviewer への指示範囲を絞るだけで、reviewer 起動・GitHub review 投稿の必須要件は変えない

## 変更履歴（git log より自動生成）

- cbe90ba fix(#187): refresh pr base before each review round
- b74d919 fix(#189): use codex exec for structured pr reviews
- d94812c feat(#185): add autonomous cross-agent PR review workflow
