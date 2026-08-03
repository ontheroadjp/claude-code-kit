# test-pr-review.sh specification

## 目的・役割

`tests/commands/test-pr-review.sh` は `/pr-review`・`/pr-review-exec`・`/git-pr` の宣言的 workflow contract を静的に検証する shell test である。Markdown command は直接実行可能なプログラムではないため、安全上重要な必須句と禁止コマンドを固定する。

根拠: `tests/commands/test-pr-review.sh:1-10`

## 動作の概要

`rg --fixed-strings` を使う `assert_contains` と `assert_absent` により、command/skill の契約を検査する。全 case を実行して failure 数を集計し、1件以上なら exit 1、全件成功なら exit 0 を返す。

根拠: `tests/commands/test-pr-review.sh:12-38`

## 検証対象

- 最大3ラウンド
- `CURRENT_AGENT` に応じて同じツールの fresh sub-agent を reviewer として起動すること（opposite-agent routing の廃止）、reviewer token の優先順位（`AI_REVIEW_TOKEN` → `CODEX_REVIEW_TOKEN`）
- reviewer identity の検証
- Codex reviewer が `--sandbox workspace-write` + `network_access=true` + `--skip-git-repo-check`（scratch cwd）で実行され、sandbox bypass をデフォルトで使わないこと。orchestrator が `GH_REPO_FULL_NAME` を解決すること
- Claude reviewer が `Read` と `gh pr diff` / `gh pr view` / `gh pr review` に限定した `Bash` だけを持ち、`Edit`/`Write` を持たないこと
- orchestrator が `commands/pr-review-exec.md` へレビュー実行を委譲すること
- reviewer が実際に新規 review を投稿したか（`PREV_REVIEW_ID`）、投稿された review の `commitId` が現在の `headRefOid` と一致するかを orchestrator が確認すること
- session-approved による修正範囲制限
- merge、main checkout/pull、branch deletion の禁止
- 旧設計（SHA固定・diffファイル事前生成・drift検知・incremental diff・trivial round分類・confirm-onlyモード・reviewerのテキスト出力契約）が orchestrator から削除されていること
- `commands/pr-review-exec.md` が自分で diff を取得し（`gh pr diff`）、`--approve`/`--request-changes` を直接投稿し、他コマンドを呼び出さず、commit/push/merge を行わないこと
- `/git-pr` から `/pr-review` への handoff
- `skills/pr-review/SKILL.md`・`skills/pr-review-exec/SKILL.md` の source-of-truth path

根拠: `tests/commands/test-pr-review.sh:40-91`

## 重要な設計判断

禁止操作は command の説明文ではなく、実行可能な shell 断片として現れる固定文字列を検出する。必須要素と禁止要素を同じ test で扱うことで、「機能追加時に安全境界だけ脱落する」変更を検知する。

旧設計（incremental diff・trivial round・SHA固定）を復活させる変更を防ぐため、それらのキーワード（`TRIVIAL_FIX_MAX_LINES`、`trivial.flag`、`confirm-only`、`incremental.diff`、`PREV_REVIEWED_SHA`、`REVIEWED_HEAD_SHA`、`base-sha.txt`）が `commands/pr-review.md` に存在しないことを明示的に assert する。

根拠: `tests/commands/test-pr-review.sh:66-74`

## 統合ポイント

- 対象: `commands/pr-review.md`、`commands/pr-review-exec.md`、`commands/git-pr.md`、`skills/pr-review/SKILL.md`、`skills/pr-review-exec/SKILL.md`
- 実行: `bash tests/commands/test-pr-review.sh`
- 依存: Bash、ripgrep (`rg`)

## 注意事項・既知の制限

- 静的 contract test であり、外部 CLI や GitHub API の実通信は行わない
- Codex reviewer の sandbox 初期化がネストしたサンドボックス環境で失敗し `--dangerously-bypass-approvals-and-sandbox` へフォールバックした場合、reviewer subprocess の安全境界が `pr-review-exec.md` の指示への準拠のみに依存する点は、静的 contract test では検出できない
- 文言変更時は意図した契約変更か確認して test pattern も更新する

## 変更履歴（git log より自動生成）

- 57c46a5 fix(#203): detect head drift between diff fetch and review post, sync stale sandbox docs
- 3e11c77 fix(#203): resolve pr-review-exec repo/sandbox failures found in live PR review
- 14b4255 refactor(#203): decouple pr-review reviewer execution into pr-review-exec
- 9d2d38f fix(#201): guard incremental pr-review diff against base drift and mode-selection ambiguity
- ad8e042 feat(#201): scope pr-review rounds to incremental diff and add trivial-fix confirm-only mode
- cbe90ba fix(#187): refresh pr base before each review round
- b74d919 fix(#189): use codex exec for structured pr reviews
- d94812c feat(#185): add autonomous cross-agent PR review workflow
