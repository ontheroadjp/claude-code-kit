# hooks/

Claude Code および Codex CLI の hook scripts を置くディレクトリ。

## 仕組み

`install.sh` が各 `.sh` ファイルを `~/.claude/hooks/` と `~/.codex/hooks/` に symlink し、
`~/.claude/settings.json`（Claude 用）と `~/.codex/hooks.json`（Codex 用）に hook エントリを登録する。

Claude Code は hook イベント発生時に登録された script を実行し、script の JSON 出力によって
ツール呼び出しの承認・ブロック・ユーザー確認フォールバックを制御する。

## イベントとセマンティクス

| イベント | 対応 hook | 役割 |
|---|---|---|
| `PreToolUse` | `auto-approve-readonly.sh`, `guard-destructive-cmd.sh` | ツール呼び出し前の承認・ブロック判定 |
| `PostToolUse` | `log-access-tool.sh`, `tmux-agent-status.sh` | ツール実行後のログ記録・ステータス更新 |
| `UserPromptSubmit` | `log-access-prompt.sh`, `tmux-agent-status.sh` | ユーザー入力受信時のログ記録 |
| `Notification` | `tmux-agent-status.sh` | 権限要求・通知発生時のステータス更新 |
| `Stop` | `cleanup-session.sh`, `log-access-stop.sh`, `log-token-usage.sh`, `tmux-agent-status.sh` | セッション終了時のクリーンアップとログ集計 |

## ファイル一覧

| ファイル | 用途 |
|---|---|
| `auto-approve-readonly.sh` | PreToolUse hook。Read・読み取り専用 Bash・session-approved カテゴリを自動承認。作業 repo 内の Write/Edit/apply_patch は WIP commit 後に承認 |
| `guard-destructive-cmd.sh` | PreToolUse hook。`lib/approval-safety.sh` を使って破壊的 Bash コマンドをブロックする wrapper |
| `cleanup-session.sh` | Stop hook。`session-approved` ファイルを削除し、空になった session ディレクトリを削除する |
| `log-access-prompt.sh` | UserPromptSubmit hook。ユーザー指示を session ファイルと月次ログに記録 |
| `log-access-tool.sh` | PostToolUse hook。tool アクセスと変更ファイルを記録 |
| `log-access-stop.sh` | Stop hook。セッション終了を月次ログに記録 |
| `log-token-usage.sh` | Stop hook。transcript の token 使用量を集計してログに追記 |

## Work-run correlation

`scripts/work-run-events.sh` が `logs/work-runs/<YYYY-MM>/<work_run_id>.jsonl` に privacy-preserving な semantic lifecycle event を記録する。各 event の `agent_session_id` は access、auto-approval、token-usage logs の session ID と同じ resolver に基づく join key であり、既存ログの内容を work-run JSONL へ複製しない。delegated worker は親から渡された `work_run_id` に attach するため、agent session が異なっても同じ logical run に関連付けられる。

work-run event は固定 schema の識別子・状態・結果だけを許可し、full prompt、agent response、source/diff body、tool input/output を拒否する。writer と各 workflow call は fail-open であり、logging failure は implementation workflow を停止・変更しない。
| `notify-slack.sh` | 任意用途の Slack 通知 helper（hook から呼び出して使う） |
| `tmux-agent-status.sh` | tmux ウィンドウタイトルに AI エージェントの状態（✅/🔵/🔴）を表示 |
| `lib/` | hook 間で共有する helper 関数ライブラリ |

## 承認フローの概要（auto-approve-readonly.sh）

```
PreToolUse イベント
  │
  ├─ session-approved fast path → 承認
  ├─ Read ツール → 承認
  ├─ 読み取り専用 Bash → 承認
  ├─ 作業 repo 内 Write/Edit/apply_patch → WIP commit → 承認
  ├─ 破壊的操作 → ブロック
  └─ 分類不能 → ユーザー確認フォールバック
```

## 使い方

```bash
# インストール（symlink 作成と settings 登録）
./install.sh

# hook を手動テストする場合
bash tests/hooks/test-approval-hooks.sh
```

tmux ステータス表示を有効にするには `~/.zshrc` に以下を追加する:

```bash
claude() { bash ~/.claude/hooks/tmux-agent-status.sh ✅; command claude "$@"; }
codex()  { bash ~/.claude/hooks/tmux-agent-status.sh ✅; command codex  "$@"; }
```
