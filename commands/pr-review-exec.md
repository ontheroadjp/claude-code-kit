# /pr-review-exec

指定した PR の diff を自分で取得してレビューし、結果を GitHub review として直接投稿する、reviewer 専用の単発実行コマンドです。実装・修正・他コマンドの呼び出しは一切行いません。

**使用方法:** `/pr-review-exec #N` または `/pr-review-exec N`

> **責務境界:** このコマンドは指定 PR の diff 取得とレビュー結果の GitHub への投稿のみを行う。`/work`・`/task`・`/patch`・`/pr-review`・`/review-resolve` など他のコマンドは実行しない。ファイルの Edit・Write、git write 操作（commit / push / stash 等）、PR の merge・close・branch 削除・main checkout は一切行わない。

---

## 前提

- 環境変数 `REVIEW_TOKEN` に GitHub token が設定されていること。未設定または空の場合は「REVIEW_TOKEN が設定されていません」と報告して終了する
- 環境変数 `GH_REPO`（`owner/repo` 形式）が設定されていること。このコマンドはリポジトリの working tree の外（sandbox 制約回避のための scratch ディレクトリ等）で実行される場合があり、その場合 `gh` は cwd から対象リポジトリを推測できない。未設定または空の場合は「GH_REPO が設定されていません」と報告して終了する
- 環境変数 `REPO_ROOT`（このリポジトリのローカル絶対パス）が設定されている場合、Step 3 の `CLAUDE.md` / `AGENTS.md` はそこを起点に読む。未設定の場合はカレントディレクトリを起点に読む
- GitHub への読み取り・書き込みは必ず `gh` CLI 経由で行う。Codex の `codex_apps` など、別アカウントで認証済みの可能性がある GitHub 統合ツール（MCP等）は使用しない — 誤ったアカウントでの読み取り・投稿を避けるため
- 最初に一度だけ `export GH_TOKEN="$REVIEW_TOKEN"` を実行し、以降の `gh` コマンドは `GH_TOKEN=... gh ...` のようにインラインで環境変数を前置せず `gh ...` の形で呼び出す。呼び出し元の tool allowlist（例: `Bash(gh pr view *)`）は「コマンドが `gh` で始まる」ことを前提にパターンマッチしており、インライン環境変数プレフィックスを付けるとマッチせず拒否されることを実地確認で発見した
- reviewer と PR author のアカウント分離確認は呼び出し元（通常 `/pr-review`）の責務であり、このコマンドはそれを検証しない。呼び出し元が確認済みの前提で動作する
- token の値は表示・ファイル保存・ログ出力しない

---

## Step 0: 引数チェック

`$ARGUMENTS` から PR 番号を取得する。`#N` の `#` は除去する。番号がなければ使用方法を報告して終了する。

## Step 1: PR の状態確認

```bash
gh pr view <PR番号> --repo "$GH_REPO" --json number,url,title,body,state,headRefName,baseRefName,headRefOid
```

- PR が存在しない、または `state` が `OPEN` でない場合: その旨を報告して終了する（review を投稿しない）
- 取得した `headRefOid` を `REVIEWED_HEAD_SHA` として保持する（Step 4 で投稿直前の再確認に使う）

## Step 2: レビュー材料の取得

このコマンドはローカルの git working tree に触れない。全て `gh` 経由でリモートから取得する。

```bash
gh pr diff <PR番号> --repo "$GH_REPO"
gh pr view <PR番号> --repo "$GH_REPO" --json title,body,comments,reviews
```

- 過去の review・comment には、これまでのラウンドで指摘した blocking finding が含まれ得る。今回の diff でそれが解消されているかどうかの判断材料として使う

## Step 3: レビュー

- `${REPO_ROOT:-.}/CLAUDE.md` / `${REPO_ROOT:-.}/AGENTS.md` と Step 2 の diff を根拠にレビューする
- ファイルの Edit・Write は行わない。read-only な調査操作（`Read`、`gh`・`git` の読み取り系コマンド）のみを使う
- 日本語で回答する
- blocking な指摘が 1 件でもあれば `REQUEST_CHANGES`、なければ `APPROVE` と判定する
- 過去の review で指摘した blocking finding が今回の diff で解消されているかどうかも判定に含める

## Step 4: GitHub への投稿

投稿直前に現在の HEAD を再確認する:

```bash
gh pr view <PR番号> --repo "$GH_REPO" --json headRefOid --jq '.headRefOid'
```

取得した値が `REVIEWED_HEAD_SHA`（Step 1 で記録）と一致しない場合: レビュー対象の diff を取得した後に新しい commit が push されたことを意味する。この場合は review を投稿せず、「対象 PR の HEAD が review 中に変化したため投稿を中止しました。再実行が必要です」と報告して終了する。

一致する場合、review 本文には判定結果の要約と finding の一覧（blocking / suggestion を区別する）を含める。

APPROVE の場合:

```bash
gh pr review <PR番号> --repo "$GH_REPO" --approve --body "<review本文>"
```

REQUEST_CHANGES の場合:

```bash
gh pr review <PR番号> --repo "$GH_REPO" --request-changes --body "<review本文>"
```

投稿に失敗した場合はエラー内容を報告して終了する。

## Step 5: 完了報告

投稿した PR 番号・判定結果（APPROVE / REQUEST_CHANGES）・blocking finding の件数を報告する。
