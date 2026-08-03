# /pr-review-exec specification

## 目的・役割

`commands/pr-review-exec.md` は、指定した PR の diff を自分で取得してレビューし、結果を GitHub review として直接投稿する、reviewer 専用の単発実行コマンドである。`commands/pr-review.md` が起動する reviewer subprocess から実行されることを主用途とするが、`/work` を経由しない自己完結コマンドとして人間が直接呼び出すこともできる。

ファイル編集・git write 操作（commit/push/stash 等）・他コマンドの呼び出し（`/work`・`/task`・`/patch`・`/pr-review`・`/review-resolve`）・PR の merge/close/branch 削除/main checkout は一切行わない。

根拠: `commands/pr-review-exec.md:1-9`

## 動作の概要

```
引数チェック（PR番号）
  → REVIEW_TOKEN の存在確認
  → PR の状態確認（存在し OPEN であること）
  → gh pr diff / gh pr view でレビュー材料を取得（ローカル working tree は使わない）
  → CLAUDE.md / AGENTS.md と diff を根拠にレビュー（read-only）
  → blocking finding の有無で APPROVE / REQUEST_CHANGES を判定
  → gh pr review --approve / --request-changes で直接投稿
  → 投稿結果を報告
```

根拠: `commands/pr-review-exec.md:16-83`

## 主要な判定ロジック

### reviewer/実装元のアカウント分離を検証しない

このコマンドは呼び出し元（通常 `commands/pr-review.md`）が reviewer と PR author のアカウント分離を確認済みである前提で動作し、自らはその検証を行わない。責務を「diff 取得・レビュー・投稿」だけに絞るための意図的な設計であり、直接呼び出す場合はアカウント分離を呼び出し側が保証する必要がある。

根拠: `commands/pr-review-exec.md:11-13`

### ローカル working tree に触れない

diff・PR 本文・過去の review/comment はすべて `gh pr diff` / `gh pr view` で GitHub から直接取得する。`git fetch` や `git checkout` を行わないため、reviewer subprocess をリポジトリの working tree と切り離して（別ディレクトリ・別サンドボックスで）実行できる。

根拠: `commands/pr-review-exec.md:29-38`

### 過去の review を context として使う

`gh pr view --json ...,comments,reviews` で取得した過去の review・comment を、直前ラウンドで指摘した blocking finding が今回の diff で解消されているかどうかの判断材料に使う。専用の「confirm-only モード」のような特別扱いはせず、常にフルの diff とレビュー判断を行う。

根拠: `commands/pr-review-exec.md:31-52`

## 重要な設計判断

### 専用コマンドとして切り出した理由

以前は reviewer subprocess への指示を `commands/pr-review.md` のオーケストレーターがプロンプト文字列としてインラインで組み立てていた。この構成では、reviewer subprocess がこのリポジトリ内で実行される際に自動的に読み込む `CLAUDE.md` の「PR 作成後の自律レビューは `/pr-review` を呼ぶこと」という override 指示と衝突し、reviewer が自分の役割（レビューと投稿）を超えてコマンドルーティングを再考してしまう問題があった。

`pr-review-exec.md` を独立した自己完結コマンドとして切り出し、`CLAUDE.md` のルーティング表にも明記することで、reviewer が `CLAUDE.md` を読んでも矛盾なく「reviewer role としては `/pr-review-exec` を使う」と判断できるようにした。プロンプト側で「CLAUDE.md の指示を無視しろ」と上書きを試みる方式は、`CLAUDE.md` 自身の「必ず従うこと」という強い宣言と矛盾し不安定になるため採用しなかった。

根拠: `CLAUDE.md:13-18`, `commands/pr-review-exec.md:1-9`

### GitHub への投稿を reviewer 自身が行う理由

`commands/pr-review.md` の設計判断を参照。

根拠: `commands/pr-review.md` の「reviewer に GitHub 書き込み権限を直接与える理由」

## 統合ポイント

- 呼び出し元: `commands/pr-review.md` Step 4.2（`codex exec` / `claude -p` から実行される）
- 手動呼び出し: `/pr-review-exec #<PR番号>`（`REVIEW_TOKEN` を呼び出し側で用意する必要がある）
- GitHub: `gh pr view`、`gh pr diff`、`gh pr review`

## 注意事項・既知の制限

- `REVIEW_TOKEN` が未設定の場合は何もせず終了する
- reviewer と PR author のアカウント分離はこのコマンド自身では検証しない
- PR が存在しない、または `OPEN` でない場合は review を投稿しない
- 投稿失敗時はエラーを報告するのみで、リトライやフォールバック投稿は行わない

## 変更履歴（git log より自動生成）

（新規追加）
