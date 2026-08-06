# /codex-review

Codex CLI を使って指定した PR をレビューし、結果を PR コメントとして投稿します。

**使用方法:** `/codex-review #N` または `/codex-review N`

> **注意（読み込み制限）**: このファイルは実行開始時に 1 回だけ Read すること。実行フロー中に確認・検証のために再度 Read しない。必要な情報はこの 1 回の読み込みで把握し、コンテキストを保持して進むこと。

---

## Step 0: 引数チェック

`$ARGUMENTS` から PR 番号を取得する。
- `#N` 形式の場合は `#` を除去して `N` として扱う
- PR 番号が指定されていない場合:
  - 「PR 番号を指定してください。例: `/codex-review #19`」と報告して終了する

---

## Step 1: PR の存在確認

```bash
gh pr view <PR番号> --json number,url,title,headRefName,baseRefName
```

- PR が存在しない場合: 「PR #<番号> が見つかりません」と報告して終了する
- PR が存在する場合: タイトル・URL・headRefName・baseRefName を記録して Step 2 へ進む

---

## Step 2: PR ブランチへの切り替え

現在のブランチを記録し、未コミット変更を退避してから PR ブランチに切り替える。

```bash
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
```

- `CURRENT_BRANCH` が `HEAD` の場合（detached HEAD 状態）:
  - 「detached HEAD 状態のため実行できません。ブランチを checkout してから再実行してください」と報告して終了する

未コミット変更を退避する:

```bash
STASHED=false
if [ -n "$(git status --porcelain)" ]; then
  git stash push -m "codex-review: auto stash"
  STASHED=true
fi
```

PR ブランチに切り替え、ベースブランチを取得する（fork PR も正しく処理される）:

```bash
gh pr checkout <PR番号>
git fetch origin <baseRefName>
```

- `gh pr checkout` に失敗した場合:
  - `$STASHED` が `true` の場合は `git stash pop` を実行する
  - 「PR #<PR番号> のブランチへの切り替えに失敗しました」と報告して終了する

---

## Step 3: Codex CLI によるレビュー実行

> **バージョン依存の注意**: `codex review --base <BRANCH>` は `[PROMPT]` 引数（カスタムレビュー指示）と併用できない（`codex-cli 0.146.1` で確認済み。`error: the argument '--base <BRANCH>' cannot be used with '[PROMPT]'`, exit 2）。`codex exec review` サブコマンドも同一の制約を持つ。将来の `codex-cli` でこの制約が変わっていないか怪しい場合は、まず `codex --version` と `codex review --help` を確認すること（`gh` について CLAUDE.md の Local Tooling Environment に記載されている手順と同様の考え方）。
>
> このため `codex review`/`codex exec review` の `--base` は使わず、トップレベルの `codex exec` に切り替える。diff の取得は **`git diff` を codex 自身に実行させず、事前にこちら側で取得してプロンプトへ渡す**（`--sandbox read-only` と併用）。プロンプト内で「まず `git diff` を実行して」と指示する方式は実機検証で試したが、codex エージェントが「このリポジトリ」という文脈から自律的に `/work` スキルの読み込みなど無関係な探索行動に入り、`git diff` の実行自体が完了しないままタイムアウトする事例を確認したため不採用とした。

以下の手順で diff を取得し、`codex exec`（`review` サブコマンドではなくトップレベルの `exec`）に `<stdin>` ブロックとして渡す。`-o/--output-last-message` で最終メッセージのみを一時ファイルに保存して端末に表示する。

```bash
TMPFILE="/tmp/codex-review-<PR番号>-$$.txt"
DIFFFILE="/tmp/codex-review-<PR番号>-$$.diff"

git diff "origin/<baseRefName>...HEAD" > "$DIFFFILE"

codex exec \
  -o "$TMPFILE" \
  --sandbox read-only \
  "以下の <stdin> ブロックに含まれる unified diff（PR #<PR番号>「<PR タイトル>」の origin/<baseRefName> との差分）をレビューしてください。diff を再取得するためのコマンド実行は行わず、与えられたテキストのみを事実として判断してください。レビューは全て日本語で回答してください。このリポジトリは Claude Code / Codex CLI 向けのコマンド・フック・スキル・設定を管理するツールキットです。以下のリポジトリ固有ルールを適用してください:
- symlink-only 原則: ~/.claude/ 配下には実体ファイルを置かず、全て本リポジトリへの symlink とする
- コミット形式: <type>(#<issue number>): <short description> (Conventional Commits)
- docs/* 変更は /docs-sync が担う（実装者が直接編集しない）
- ワークスペースのクリーン化は stash で行う（破壊的操作禁止）
- git diff が事実。AI の要約・解釈は補助情報にとどめる" \
  < "$DIFFFILE" > /dev/null
cat "$TMPFILE"
```

- コマンドが失敗した場合: 「codex review の実行に失敗しました」と報告して Step 4 へ進み、Step 4 完了後に終了する（Step 5 以降は実行しない）

---

## Step 4: 元のブランチに戻る

```bash
git checkout "$CURRENT_BRANCH"
if [ "$STASHED" = "true" ]; then
  git stash pop
fi
```

---

## Step 5: PR レビューとして投稿

ANSI エスケープシーケンスを除去し、Codex 出力の内容を判定して PR レビューを提出する。

```bash
CLEAN_TMPFILE="${TMPFILE}.clean"
sed $'s/\033\[[0-9;]*[mGKHF]//g' "$TMPFILE" > "$CLEAN_TMPFILE"
```

`$CLEAN_TMPFILE` の内容を読み、以下の基準で判定する:
- 問題点・バグ・修正提案・セキュリティ懸念・重大な指摘が**含まれていない** → **問題なし**
- 上記のいずれかが**含まれている** → **問題あり**

`CODEX_REVIEW_TOKEN` 環境変数が設定されているか確認する。

**設定されていない場合:**

以下のエラーを報告し、`rm -f "$TMPFILE" "$CLEAN_TMPFILE" "$DIFFFILE"` を実行して終了する:

```
エラー: CODEX_REVIEW_TOKEN が設定されていません。
GitHub は PR 作者自身による --approve / --request-changes を禁止するため、別アカウントの PAT が必要です。
~/.claude/settings.local.json に以下を追加してください:
{
  "env": {
    "CODEX_REVIEW_TOKEN": "<別アカウントの PAT>"
  }
}
```

**設定されている場合:**

問題なしの場合:
```bash
GH_TOKEN="$CODEX_REVIEW_TOKEN" gh pr review <PR番号> --approve --body-file "$CLEAN_TMPFILE"
```

問題ありの場合:
```bash
GH_TOKEN="$CODEX_REVIEW_TOKEN" gh pr review <PR番号> --request-changes --body-file "$CLEAN_TMPFILE"
```

- 投稿に失敗した場合: `rm -f "$TMPFILE" "$CLEAN_TMPFILE" "$DIFFFILE"` を実行し、「レビューの投稿に失敗しました。レビュー結果は削除されました」と報告して終了する

---

## Step 6: 一時ファイルの削除と完了報告

```bash
rm -f "$TMPFILE" "$CLEAN_TMPFILE" "$DIFFFILE"
```

ユーザーに以下を報告する:

- 問題なし: 「PR #<PR番号> を承認しました（Codex レビュー: 問題なし）」
- 問題あり: 「PR #<PR番号> に変更リクエストを提出しました（Codex レビュー: 問題あり）」

問題ありの場合、報告後に続けて `/review-resolve #<PR番号>` を自動実行する。
