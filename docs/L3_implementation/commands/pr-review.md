# /pr-review specification

## 目的・役割

`commands/pr-review.md` は、ready PR を実装元とは別の AI agent でレビューし、妥当な blocking finding を承認済みスコープ内で修正・再レビューして、最新 HEAD を `APPROVED` または `CHANGES_REQUESTED` に更新する。diff の取得とレビュー結果の GitHub 投稿自体は行わず、`commands/pr-review-exec.md` に委譲する薄いオーケストレーターである。

責務は review 済み PR の作成までであり、merge、branch 削除、main checkout、main pull は人間の管理下に残す。

根拠: `commands/pr-review.md:1-15`

## 動作の概要

```
引数・実装 agent 判定
  → PR/workspace gate（Step 4.5 の修正作業用に PR branch を checkout）
  → 別 GitHub reviewer identity の確認（ラウンド共通で使い回す）
  → 各ラウンドで投稿済み review の起点（PREV_REVIEW_ID）を記録
  → reviewer subprocess に pr-review-exec.md を実行させる（diff 取得〜GitHub 投稿は reviewer 自身が行う）
  → 新規投稿の有無・commitId が現在の headRefOid と一致するかを確認
  → APPROVED ならそのまま終了、REQUEST_CHANGES なら元 agent が検証・修正・commit・push
  → 最大3ラウンド再レビュー
  → APPROVED / CHANGES_REQUESTED / FAILED で終了
```

根拠: `commands/pr-review.md:18-34`, `commands/pr-review.md:77-155`

## 主要な判定ロジック

### opposite-agent routing

`CODEX_THREAD_ID` または `CODEX_CI` がある場合は Codex を実装元、Claude を reviewer とする。それ以外は Claude を実装元、Codex を reviewer とする。環境判定ができない場合は現在の agent を明示的に実装元として確定し、同じ agent に自己レビューさせない。

根拠: `commands/pr-review.md:17-33`

### reviewer identity

GitHub review 投稿には `AI_REVIEW_TOKEN` を優先し、既存 `CODEX_REVIEW_TOKEN` を fallback として使う。token の login が PR author と一致する場合は停止する。この確認は Step 2 で 1 度だけ行い、全ラウンドで使い回す。token 値は表示・保存しない。

根拠: `commands/pr-review.md:51-64`

### reviewer subprocess の実行と sandbox/権限設計

Codex reviewer は `commands/pr-review-exec.md` をリポジトリ外の scratch ディレクトリ（`--cd`）で `--dangerously-bypass-approvals-and-sandbox` を用いて実行する。当初は `--sandbox workspace-write` + `sandbox_workspace_write.network_access=true` で cwd 配下だけ書き込み可能にしたまま `gh` のネットワーク呼び出しを許可する設計だったが、bubblewrap によるサンドボックス初期化がホスト環境（ネストした user namespace を作れない環境等）によっては `Permission denied` で失敗し、`gh` を含む全てのコマンドが実行できなくなることが実地確認で判明した。そのため OS レベルの sandbox には依存せず、scratch cwd（相対パスの誤書き込み防止）と `pr-review-exec.md` に明記された「ファイル編集・他コマンド呼び出しをしない」という指示だけを安全境界とする設計に変更した。

reviewer は working tree の外で実行されるため `gh` が対象リポジトリを推測できない。orchestrator は `GH_REPO_FULL_NAME`（`gh repo view --json nameWithOwner`）を Step 1 で取得し、reviewer subprocess に `GH_REPO` として渡す。`pr-review-exec.md` はこれを必須の前提とし、全ての `gh pr` コマンドに `--repo "$GH_REPO"` を明示する。同様に `REPO_ROOT` を渡し、scratch cwd から `CLAUDE.md` / `AGENTS.md` を正しい絶対パスで読めるようにする。

Claude reviewer は OS レベルの sandbox を持たないため、`--tools "Read,Bash"` と `--allowedTools` で `Bash` を `gh pr diff` / `gh pr view` / `gh pr review` / `gh api user` の各サブコマンドだけに制限し、`Edit`/`Write` を与えないことで同等の書き込み境界を作る。

いずれの reviewer にも `commands/pr-review.md` 自身への書き込み権限や、`/work`・`/task`・`/patch`・`/pr-review` 等の他コマンドを実行する経路を与えない。実地検証で、sandbox が機能しない場合に Codex が自前の `codex_apps` GitHub 統合（reviewer とは別の、Codex に既にログイン済みのアカウントで認証されている）に読み取りだけフォールバックする挙動を確認した。書き込みには使われなかったが、`pr-review-exec.md` は `gh` CLI 以外の GitHub 統合ツールの使用を明示的に禁止することでこの経路を塞ぐ。

根拠: `commands/pr-review.md:38-39`, `commands/pr-review.md:93-124`

### 投稿結果の確認（新規投稿検出と commit 一致）

reviewer 起動前に `REVIEWER_LOGIN` による最新 review の ID を `PREV_REVIEW_ID` として記録する。起動後、同じ query を再実行し、`id` が変化していなければ reviewer が review を投稿できなかったとみなし `FAILED` とする。新規投稿があれば、その `commitId` が現在の `headRefOid` と一致するかを確認し、一致しない場合も `FAILED` とする。

根拠: `commands/pr-review.md:124-134`

### bounded remediation

review は `MAX_REVIEW_ROUNDS=3` に制限する。元 agent は finding の妥当性をコードと docs から再検証し、session-approved 内だけを修正する。最終ラウンドの変更要求、スコープ拡大、破壊的操作、秘密情報、権限追加が必要な finding は自動修正せず `CHANGES_REQUESTED` で人間へ返す。

根拠: `commands/pr-review.md:11-16`, `commands/pr-review.md:139-155`

## 重要な設計判断

### diff 取得・SHA 固定・drift 検知・trivial round 分類を廃止した理由

従来の設計は、orchestrator が各ラウンドで base branch を fetch し、reviewer 用の diff ファイルを事前生成し、HEAD SHA を固定し、round 2 以降は増分 diff・trivial round・confirm-only モードでレビュー範囲を絞る、という複雑な事前計算を行っていた。この機構は「reviewer subprocess をコールドスタートで毎ラウンド起動すると遅い」という問題への最適化だったが、レイテンシと複雑さの増大に見合わなかった。

加えて、reviewer subprocess はこのリポジトリのディレクトリ内で実行されるため `CLAUDE.md` が project instructions として自動的に見えており、「PR 作成後の自律レビューは `/pr-review` を呼ぶこと」という override 指示に反応して、reviewer が本来のスコープ外（コマンドルーティングや設計思想の理解）にまで踏み込んでしまう問題があった。

これらを解決するため、reviewer が diff 取得から GitHub への review 投稿までを `pr-review-exec.md` として自己完結させ、orchestrator は identity 確認とラウンド管理だけに縮小した。`pr-review-exec.md` は `CLAUDE.md` のルーティング表にも自己完結フローとして明記されているため、reviewer が `CLAUDE.md` を読んでも `/pr-review` へ迷い込まない。

根拠: `commands/pr-review.md:92-123`, `CLAUDE.md:13-18`

### reviewer に GitHub 書き込み権限を直接与える理由

このリポジトリの運用では PR は実装元 agent 自身が作成し、reviewer に渡るまでの時間差は数秒〜数分程度である。この条件下では、diff の内容が第三者に改ざんされる余地（prompt injection の主要な脅威モデル）はごく限定的であり、orchestrator が reviewer の出力をテキスト契約としてパースしてから代理投稿するという中継コストに見合わないと判断した。そのため reviewer 自身が `REVIEW_TOKEN` を用いて `gh pr review` を直接実行する設計に変更した。ただし reviewer と PR author のアカウント分離確認（Step 2）は orchestrator 側に残し、投稿前に必ず別アカウントであることを検証する。

根拠: `commands/pr-review.md:51-64`, `commands/pr-review-exec.md:1-16`

### merge を行わない理由

AI に review と修正の反復を任せつつ、main への統合は人間の明示操作として残すためである。review が失敗または収束しない場合も PR を保持し、現在状態から人間が判断できる。

根拠: `commands/pr-review.md:3-7`, `commands/pr-review.md:157-163`

## 統合ポイント

- 自動呼び出し元: `commands/git-pr.md` Step 8
- 手動呼び出し: `/pr-review #<PR番号>`
- reviewer 実行委譲先: `commands/pr-review-exec.md`（`codex exec --sandbox workspace-write` または `claude -p --tools "Read,Bash"` から実行される）
- commit/docs: `/git-commit`、必要な場合は `/docs-sync`
- GitHub: `gh pr view`、`gh pr checkout`、`gh api user`
- 一時ファイル: `/tmp/claude-code-kit/<session-id>/pr-review-<PR番号>/`（reviewer subprocess の scratch ディレクトリと起動ログのみ）

## 注意事項・既知の制限

- reviewer 投稿には PR author と異なる GitHub account の token が必要
- 自動修正は現在の session-approved に登録済みのファイルとツールに限定される
- reviewer subprocess が review を投稿しなかった場合（`PREV_REVIEW_ID` から変化なし）は `FAILED` で終了する
- 投稿された review の `commitId` が現在の `headRefOid` と一致しない場合も `FAILED` で終了する
- PR merge、close、branch 削除、main 同期は行わない
- 3ラウンドで収束しない finding は人間判断へ返す
- Codex reviewer の `workspace-write` + `network_access=true` の組み合わせで実際に `gh` のネットワーク呼び出しが通るかは、実 PR を使った実地確認が必要（このリポジトリのテストは静的 contract test のみで、実際の CLI 実行は検証しない）

## 変更履歴（git log より自動生成）

- 3e11c77 fix(#203): resolve pr-review-exec repo/sandbox failures found in live PR review
- 14b4255 refactor(#203): decouple pr-review reviewer execution into pr-review-exec
- 2dcec34 fix(#201): decouple incremental-diff generation from what the reviewer actually receives
- b128570 fix(#201): measure trivial-fix line counts before commit and align L3 doc with source of truth
- 9d2d38f fix(#201): guard incremental pr-review diff against base drift and mode-selection ambiguity
- ad8e042 feat(#201): scope pr-review rounds to incremental diff and add trivial-fix confirm-only mode
- cbe90ba fix(#187): refresh pr base before each review round
- b74d919 fix(#189): use codex exec for structured pr reviews
- d94812c feat(#185): add autonomous cross-agent PR review workflow
