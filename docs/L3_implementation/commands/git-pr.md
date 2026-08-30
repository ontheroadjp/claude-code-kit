# /git-pr specification

## 目的・役割

`commands/git-pr.md` は `git push` と `gh pr create` を担うスラッシュコマンドである。`/git-commit` が commit 操作を集約するのと同様に、push・PR 作成操作をここに集約する。PR 作成・URL 報告でこのコマンドの責務は完結し、以降の review・merge は自動実行しない（`/work`・`/task` のゴールは ready PR の作成まで）。

`/task` Phase 2 から `/docs-sync` 完了後に呼び出される。ユーザーが手動で呼び出すこともできる。

根拠: `commands/git-pr.md:1-7`

## 動作の概要

7 ステップで構成される、PR 作成フロー:

```
Step 1: セッション temp ディレクトリの特定
Step 2: PR タイトルの準備（temp ファイルまたは git log から生成）
Step 3: PR body の準備（temp ファイルまたは diff から生成）
Step 4: docs sync 結果の追記（pr-docs-sync-result.md があれば body 末尾に追加）
Step 5: git push
Step 6: gh pr create（ready for review）
Step 7: 結果報告（PR URL。ここでフロー完結）
```

根拠: `commands/git-pr.md:12-64`

## 主要な判定ロジック

### SESSION_TMP_DIR の導出

```bash
bash ~/.claude/hooks/lib/session-paths.sh session-tmp-dir
# Codex CLI: bash ~/.codex/hooks/lib/session-paths.sh session-tmp-dir
```

出力された1行の絶対パスを `SESSION_TMP_DIR` として使用する。以前は `${STATE_ROOT}/current-session-approved-path` という共有ポインタファイルを読んでディレクトリ名からセッション ID を逆算しており（複数セッション同時実行時に他セッションのファイルを誤って参照する競合があったため issue #210 で廃止）、その後は `$CLAUDE_CODE_SESSION_ID` から直接導出する Bash スニペットをインライン展開していた。このインライン式は brace expansion と代入への command substitution を含んでおり、`/work-multi` の worktree 隔離セッションでは harness に拒否されることが判明したため、`hooks/lib/session-paths.sh` を直接実行する単一のプレーンな呼び出しに置き換えた（issue #316）。詳細は `docs/L3_implementation/hooks/lib/session-id.sh.md`、`docs/L3_implementation/hooks/lib/session-paths.sh.md` を参照。

### temp ファイルの優先順位

| ファイル | あり | なし |
|---|---|---|
| `pr-title.txt` | そのまま使用 | `git log main...HEAD --oneline` から生成 |
| `pr-body.md` | そのまま使用 | テンプレート or diff から生成 |
| `pr-docs-sync-result.md` | body 末尾に追記 | スキップ |

根拠: `commands/git-pr.md:25-45`

temp の PR body がない場合は `${TEMPLATES_DIR}/pr.md` を fallback として使う。`TEMPLATES_DIR` は Claude Code では `~/.claude/templates`、Codex CLI では `~/.codex/templates` である。

根拠: `commands/git-pr.md:7-9`, `commands/git-pr.md:33-38`

### フローの終端

Step 7 の結果報告（PR URL）でこのコマンドの責務は完結する。作成後の review・merge は自動実行せず、人間（または `/review-resolve`・`/codex-review` を手動起動するユーザー）が行う。

根拠: `commands/git-pr.md:62-65`

## 重要な設計判断

### push を /git-pr に移動した理由

従来は `/task` Phase 2 が draft PR 作成のために push し、`/docs-sync` Phase 3 が docs commit のために再度 push していた（合計 2 回）。push 後はローカルの commit 操作（amend/squash/rebase）が実質困難になるため、全コミット（実装 + docs）が確定してから 1 回だけ push する設計に変更した。

### draft → ready の遷移をなくした理由

従来は draft PR を作成し、`/docs-sync` 完了後に `gh pr ready` で公開状態に遷移していた。`/git-pr` が担うことで、docs sync 完了済みの状態で直接 ready PR を作成できるため、中間状態（draft）が不要になった。

根拠: 設計経緯は issue #167 参照

## 統合ポイント

- 呼び出し元: `commands/task.md`（Phase 2 Step 1 から `/docs-sync` 完了後に自動呼び出し）、ユーザーの手動呼び出し
- 呼び出すもの: `git push`・`gh pr create`・`hooks/lib/session-paths.sh`（`bash` で直接実行。このコマンドは他の command/skill を呼び出さない）
- fallback PR template: `${TEMPLATES_DIR}/pr.md`
- 依存 temp ファイル（任意）:
    - `SESSION_TMP_DIR/pr-title.txt`（`/task` が書き出す）
    - `SESSION_TMP_DIR/pr-body.md`（`/task` が書き出す）
    - `SESSION_TMP_DIR/pr-docs-sync-result.md`（`/docs-sync` が書き出す）

## 注意事項

- PR は ready for review として作成する（draft では作成しない）
- PR 作成・URL 報告でフローは完結し、review・merge は行わない（人間、または `/review-resolve`・`/codex-review` の手動起動に委ねる）
- SESSION_TMP_DIR が特定できない場合は temp ファイルなしとして動作する（エラーにしない）
- 手動呼び出し時に temp ファイルがなければ diff からタイトル・本文を生成するため、単独でも動作する

## 変更履歴（git log より自動生成）

- 5f3aacf feat(#401): add structured work run observability
- e7d5698 fix(#316): resolve session paths via hooks/lib/session-paths.sh to survive worktree-isolated harness guard
- db6d6c3 fix(#210): resolve session id from env instead of a shared pointer file
- 5a4ecc6 chore(#205): remove /pr-review; /work and /task now end at PR creation
- 27f1861 feat(#76): install templates for claude and codex
- d94812c feat(#185): add autonomous cross-agent PR review workflow
- 82717a1 feat(#167): add /git-pr command; refactor push and PR creation out of /task and /docs-sync

## Work-run observability

共有契約は `commands/work.md`「Work-run observability › 共有契約」を参照。`/git-pr` は作成済みPRのnumber・URL・full head SHAとissue numberを取得できた場合に `pr_created` event を emit する（取得不能なら省略）。

根拠: `commands/git-pr.md:55-74`
