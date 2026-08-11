# /review-resolve specification

## 目的・役割

`commands/review-resolve.md` は PR レビューコメントへの対話対応に特化した、`/work` を経由しない自己完結型のコマンドである。対象 PR のインラインコメント・レビュー本体コメントを 1 件ずつ提示し、ユーザーが選択した対応方針（実装/反対意見/理由付き非対応/スキップ）に従って実装・commit・push・返信までを完結させる。

根拠: `commands/review-resolve.md:1-6`

## 動作の概要

```
Step 0:   引数チェック（PR番号の取得）
Step 1:   PR の存在確認
Step 1.5: セッション内 git 書き込み操作の一括承認（session-approved ゲート）
Step 1.6: PR ブランチの取得・切り替え（fetch/checkout）
Step 2:   レビューコメントの取得（インライン + レビュー本体）
Step 3:   コメントの提示・意見・対応選択（1件ずつ）
Step 4:   完了報告
```

根拠: `commands/review-resolve.md:9-188`

## 主要なフロー

### Step 1.5: セッション内 git 書き込み操作の一括承認

`/work` を経由する `task.md`/`patch.md` は Step 2（プラン確認）で `tool:git_write` 等を session-approved ファイルへ 1 度だけ書き込み、以降のセッション内 git 書き込みを自動承認する。`/review-resolve` はこのゲートを持たず、`git fetch`/`checkout`（Step 1.6）や `git push`（Step 3 選択1）が毎回個別の許可プロンプトを要求していた。

これを解消するため、Step 1（PR 存在確認）後・Step 1.6（fetch/checkout）前に session-approved ゲートを追加した。ユーザーに一度だけ確認し、OK であれば `tool:git_write` のみを session-approved ファイルへ書き込む。task.md/patch.md と同じ仕組み（`hooks/lib/session-paths.sh session-approved` から直接パスを導出し、共有ポインタファイルは経由しない。issue #316）を再利用している。

**`tool:gh_issue_write`/`tool:gh_pr_write` は対象外:** Step 3 のコメント返信（選択 1〜3）は `gh issue comment`/`gh pr comment` ではなく `gh api repos/{owner}/{repo}/(pulls/<N>/comments/<id>/replies|issues/<N>/comments) --method POST -f body=...` を使っている。session-approved の `tool:gh_issue_write`/`tool:gh_pr_write` カテゴリはリテラルサブコマンド（`gh issue comment` 等）にのみマッチし、`gh api ... --method POST` にはマッチしないため、このゲートを追加してもコメント返信は自動承認されず、引き続き通常の許可フローに従う（`hooks/auto-approve-readonly.sh` の `is_safe_git_read_command`/`check_session_approved` は `gh api` の write 系操作を意図的に allowlist-shape の対象外としている）。

根拠: `commands/review-resolve.md:29-55`, `hooks/auto-approve-readonly.sh`（`check_session_approved`）, `docs/L3_implementation/hooks/auto_approve_readonly.md`, issue #221

## 重要な設計判断

### なぜ `git push` 相当だけを対象にしたか

`/review-resolve` の書き込み操作は「git 書き込み（fetch/checkout/add/commit/push）」と「GitHub コメント投稿（gh api 経由）」の 2 系統に分かれる。前者は `tool:git_write` という既存カテゴリでそのまま解決できるが、後者は `gh api` の write 系を無条件・カテゴリ経由のいずれでも自動承認しないという既存の安全設計（`docs/L0_concept/policy.md` の allowlist-shape 方針）に触れる。コメント返信の頻度は高いが、この安全境界を緩めることは今回のスコープ外と判断し、`tool:git_write` のみをゲート対象とした。

### なぜ `tool:gh_pr_write`/`tool:gh_issue_write` も session-approved ファイルへ含めていないか

上記の理由により、書き込んでも実際にマッチする Bash コマンドが存在しない（`gh api ... --method POST` はどちらのカテゴリにもマッチしない）。無意味なカテゴリを書き込むと将来 `gh issue comment`/`gh pr comment` のリテラル呼び出しに切り替わった際に境界が曖昧になるため、実際に効果のある `tool:git_write` のみを書き込む。

## 統合ポイント

- 呼び出し元: ユーザーが直接 `/review-resolve <PR番号>` で起動（`/work` からは呼ばれない）
- 参照する hook: `hooks/auto-approve-readonly.sh`（`check_session_approved` の `tool:git_write` カテゴリ）
- session-approved パス解決: `commands/task.md`/`commands/patch.md` と同じ導出ロジック（`hooks/lib/session-paths.sh session-approved` を直接実行、issue #316）

## 注意事項・既知の制限

- session-approved への書き込みは 1 度だけ。スコープ変更が必要な場合は Step 1.5 に戻ってユーザーの許可を得てから再書き込みする（他コマンドと同じ制約。hook がスコープ拡張を検知して block する）
- コメント返信（`gh api ... --method POST`）は本ゲートの対象外のままであり、依然として毎回の許可プロンプトが発生する

## 変更履歴（git log より自動生成）

- e7d5698 fix(#316): resolve session paths via hooks/lib/session-paths.sh to survive worktree-isolated harness guard
- 377cdd3 feat(#221): allow-shape auto-approve for local git writes, add review-resolve session gate
- 89d5fad feat(#157): move git-commit to commands/, add skill wrapper, update all callers to /git-commit
- 051fd5f fix(#113): post gh pr review instead of issue comment, add APPROVED to review-resolve
- 7536b79 fix(#58): fetch and checkout PR branch before fetching comments
- 4e87fe4 feat(#56): make /review-resolve self-contained, add opinion presentation
- b1e6623 feat(#52): add /review-resolve command for interactive PR review comment handling
