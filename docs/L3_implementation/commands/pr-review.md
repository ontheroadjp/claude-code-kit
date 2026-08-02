# /pr-review specification

## 目的・役割

`commands/pr-review.md` は、ready PR を実装元とは別の AI agent でレビューし、妥当な blocking finding を承認済みスコープ内で修正・再レビューして、最新 HEAD を `APPROVED` または `CHANGES_REQUESTED` に更新する。

責務は review 済み PR の作成までであり、merge、branch 削除、main checkout、main pull は人間の管理下に残す。

根拠: `commands/pr-review.md:1-15`, `commands/pr-review.md:182-190`

## 動作の概要

```
引数・実装 agent 判定
  → PR/workspace gate
  → 別 GitHub reviewer identity の確認
  → 最新 HEAD SHA を固定
  → opposite agent の read-only review
  → GitHub に APPROVED / CHANGES_REQUESTED を投稿
  → blocking finding があれば元 agent が検証・修正
  → 最大3ラウンド再レビュー
  → APPROVED / CHANGES_REQUESTED / FAILED で終了
```

根拠: `commands/pr-review.md:17-79`, `commands/pr-review.md:81-190`

## 主要な判定ロジック

### opposite-agent routing

`CODEX_THREAD_ID` または `CODEX_CI` がある場合は Codex を実装元、Claude を reviewer とする。それ以外は Claude を実装元、Codex を reviewer とする。環境判定ができない場合は現在の agent を明示的に実装元として確定し、同じ agent に自己レビューさせない。

根拠: `commands/pr-review.md:17-33`

### reviewer identity

GitHub review 投稿には `AI_REVIEW_TOKEN` を優先し、既存 `CODEX_REVIEW_TOKEN` を fallback として使う。token の login が PR author と一致する場合は停止する。token 値は表示・保存しない。

根拠: `commands/pr-review.md:51-64`

### review と HEAD SHA の結合

各ラウンド開始時に GitHub の `headRefOid` と local HEAD を一致させ、その SHA を reviewer 出力の `REVIEWED_HEAD_SHA` に要求する。review 投稿直前と投稿後にも SHA を照合し、approval の `commit_id` と現在の PR HEAD が一致する場合だけ `APPROVED` とする。

この多段照合により、review 中や投稿直前に追加 push があった場合に古い結果を最新 HEAD の approval として扱わない。

根拠: `commands/pr-review.md:81-105`, `commands/pr-review.md:133-162`

### bounded remediation

review は `MAX_REVIEW_ROUNDS=3` に制限する。元 agent は finding の妥当性をコードと docs から再検証し、session-approved 内だけを修正する。最終ラウンドの変更要求、スコープ拡大、破壊的操作、秘密情報、権限追加が必要な finding は自動修正せず `CHANGES_REQUESTED` で人間へ返す。

根拠: `commands/pr-review.md:11-15`, `commands/pr-review.md:164-180`

## 重要な設計判断

### reviewer subprocess を read-only にする理由

別 agent は独立した批評者であり、実装者ではない。Codex は汎用の `codex exec` を `--sandbox read-only --ephemeral` で実行し、Claude は `Read` tool のみに制限する。修正・GitHub 投稿は元 agent が担当するため、reviewer が承認済みスコープや session approval を迂回して変更する経路を作らない。

Codex の専用 review subcommand は固定の finding 形式を出力するため使用しない。汎用 exec に機械可読契約を明示し、`--output-last-message` で最終回答だけを保存することで、進行イベントを混ぜずに `VERDICT`、`REVIEWED_HEAD_SHA`、`FINDINGS` を検証できる。

根拠: `commands/pr-review.md:107-132`

### merge を行わない理由

AI に review と修正の反復を任せつつ、main への統合は人間の明示操作として残すためである。review が失敗または収束しない場合も PR を保持し、現在状態から人間が判断できる。

根拠: `commands/pr-review.md:3-7`, `commands/pr-review.md:182-190`

## 統合ポイント

- 自動呼び出し元: `commands/git-pr.md` Step 8
- 手動呼び出し: `/pr-review #<PR番号>`
- reviewer CLI: `codex exec --sandbox read-only --ephemeral` または `claude -p`
- commit/docs: `/git-commit`、必要な場合は `/docs-sync`
- GitHub: `gh pr view`、`gh pr review`、`gh api user`
- 一時ファイル: `/tmp/claude-code-kit/<session-id>/pr-review-<PR番号>/`

## 注意事項・既知の制限

- reviewer 投稿には PR author と異なる GitHub account の token が必要
- 自動修正は現在の session-approved に登録済みのファイルとツールに限定される
- Codex reviewer の機械判定には `--output-last-message` が保存した最終回答だけを使用する
- review 出力が所定形式でない場合は GitHub review を投稿せず `FAILED` で終了する
- PR merge、close、branch 削除、main 同期は行わない
- 3ラウンドで収束しない finding は人間判断へ返す

## 変更履歴（git log より自動生成）

- d94812c feat(#185): add autonomous cross-agent PR review workflow
