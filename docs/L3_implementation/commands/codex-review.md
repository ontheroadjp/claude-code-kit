# /codex-review specification

## 目的・役割

`commands/codex-review.md` は Codex CLI を使って指定した PR を非対話的にレビューし、結果を PR レビューコメント（approve / request-changes）として投稿するワークフローである。`commands/work.md` を経由せず自己完結する。

根拠: `commands/codex-review.md:1-9`

## 動作の概要

6 Step で構成される:

```
Step 0: 引数チェック（PR番号取得）
Step 1: PR の存在確認
Step 2: PR ブランチへの切り替え（未コミット変更は stash 退避）
Step 3: Codex CLI によるレビュー実行
Step 4: 元のブランチに戻る
Step 5: PR レビューとして投稿（問題なし/問題ありを判定）
Step 6: 一時ファイルの削除と完了報告
```

根拠: `commands/codex-review.md:11-158`

## 主要なフロー

### Step 3: Codex CLI によるレビュー実行

`codex review --base <BRANCH> <PROMPT>` は `codex-cli 0.146.1` で `--base` と位置引数 `[PROMPT]` が排他constraint（`error: the argument '--base <BRANCH>' cannot be used with '[PROMPT]'`, exit 2）のため使用できない。`codex exec review` サブコマンドも同一の制約を持つ。

代わりにトップレベルの `codex exec` を使い、以下の手順で diff をスコープする:

1. `git diff "origin/<baseRefName>...HEAD" > "$DIFFFILE"` で diff を事前取得する
2. `codex exec -o "$TMPFILE" --sandbox read-only "<repo-specific rules を含む固定プロンプト>" < "$DIFFFILE"` を実行する。`codex exec` は位置引数 `[PROMPT]` が与えられかつ stdin がパイプされている場合、stdin の内容を `<stdin>` ブロックとしてプロンプトに自動的に付加する（`codex exec --help` に記載の仕様）
3. `-o/--output-last-message` により、transcript ノイズを含まない最終メッセージのみが `$TMPFILE` に書き出される

根拠: `commands/codex-review.md:65-91`

### Step 5: PR レビューとして投稿

`$TMPFILE` の ANSI エスケープを除去した `$CLEAN_TMPFILE` の内容から「問題なし/問題あり」を判定し、`GH_TOKEN="$CODEX_REVIEW_TOKEN" gh pr review <PR番号> --approve|--request-changes --body-file "$CLEAN_TMPFILE"` で投稿する。`CODEX_REVIEW_TOKEN` は PR 作者自身による self-approve を GitHub が禁止するため必須（別アカウントの PAT）。

根拠: `commands/codex-review.md:100-149`

## 設計上の決断

### `codex exec` にプロンプトで `git diff` を実行させず、事前に diff を取得して渡す理由

実装時（issue #293）、プロンプト内で「まず `git diff origin/<base>...HEAD` を実行してレビューせよ」と指示する方式を実機検証した。その結果、codex エージェントが「このリポジトリ」という文脈から `/work` スキルの読み込みなど無関係な探索行動に自律的に入り、肝心の `git diff` 実行が完了しないままタイムアウトする事例を確認した。この agentic な迷走リスクを構造的に排除するため、diff の取得は呼び出し側（このワークフロー自身）が `git diff` で行い、codex には完成済みの diff テキストを `<stdin>` 経由で渡すだけにした。`--sandbox read-only` も、codex 側にコマンド実行の自由度を与えないための追加の安全策として併用している。

根拠: issue #293, `commands/codex-review.md:67`

### `-o/--output-last-message` を使う理由

`codex exec` は標準出力に hook イベントログやトークン使用量などの transcript ノイズを含めて出力する（`codex review` のような構造化レビュー専用の出力ではない）。`-o <file>` は最終的なエージェントメッセージのみをファイルに書き出すため、Step 5 の ANSI 除去・問題判定ロジックに渡す内容をノイズなく確保できる。

根拠: issue #293 実機検証, `commands/codex-review.md:69`

## 統合ポイント

- 呼び出し元: ユーザーが `/codex-review #N` で直接起動（`commands/work.md` を経由しない）
- 呼び出すもの: `commands/review-resolve.md`（Step 6 で「問題あり」の場合に自動実行）
- 外部 CLI 依存: `gh`, `codex`

## 注意事項・既知の制限

- `codex-cli` のバージョンによって `--base`/`[PROMPT]` の排他制約が変わる可能性がある。この Step が失敗する場合はまず `codex --version` と `codex review --help` を確認する
- `TMPFILE`/`DIFFFILE`/`CLEAN_TMPFILE` の一時ファイルは `/tmp/codex-review-<PR番号>-$$` 形式で作成される（`CLAUDE.md` が原則とする `/tmp/claude-code-kit/$SESSION_ID/` 配下ではない、既存の実装からの継続的な逸脱。issue #293 では新規追加した `DIFFFILE` を既存の `TMPFILE` の配置規則に合わせたのみで、この逸脱自体は本 issue のスコープ外として未対応）

## 変更履歴（git log より自動生成）

- fix(#293): codex-review の `--base`/PROMPT 競合を修正（本コミット）
- 13dbefd refactor: reduce duplicate file reads across work/task/patch/codex-review flows
- 4ba8259 feat(#115): require CODEX_REVIEW_TOKEN and auto-invoke review-resolve on changes-requested
- a474b4c fix(#113): address 3 P2 issues from Codex review
- c1a3552 fix(#113): support CODEX_REVIEW_TOKEN for gh pr review on own PRs
- 051fd5f fix(#113): post gh pr review instead of issue comment, add APPROVED to review-resolve
- d2aa807 fix(#113): address 10 bugs found by code-review in codex-review command
- b592708 feat(#113): add /codex-review command and skill
