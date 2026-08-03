# hooks/lib/

hook scripts 間で共有する Bash helper 関数ライブラリ。

## ファイル一覧

| ファイル | 用途 |
|---|---|
| `approval-safety.sh` | PreToolUse hook で使う破壊的操作検出 helper |
| `session-id.sh` | セッション ID 解決 helper |

## session-id.sh

`auto-approve-readonly.sh` と `cleanup-session.sh` の両方から `source` で読み込まれる共有 helper。

### 提供する関数

**`session_id_resolve [payload]`**

現在のセッション ID を解決する。`payload`（省略可）は hook が受け取った PreToolUse/Stop の JSON ペイロード文字列。hook 以外の文脈（`commands/*.md` の Bash スニペットなど）から呼ぶ場合は省略する。

優先順位:
1. `CLAUDE_CODE_KIT_SESSION_ID`（テスト/上書き用）
2. `CLAUDE_CODE_SESSION_ID`（Claude Code が設定するセッション ID。hook プロセスだけでなく、Bash tool が実行するシェルにも見える）
3. `payload.session_id`（hook 文脈のみ）
4. `payload.transcript_path` のハッシュ（hook 文脈のみ）
5. `CODEX_THREAD_ID` のハッシュ
6. `process-<PPID>` フォールバック（弱い。呼び出し側は「未解決」として扱うこと）

**`session_id_sanitize <value>`** / **`session_id_hash_key <value>`**

`session_id_resolve` が内部で使うサニタイズ・ハッシュ helper。単体でも利用可能。

### 使い方（hook から呼び出す例）

```bash
# hook script 内で source する
. "${REPO_DIR}/hooks/lib/session-id.sh"

SESSION_ID="$(session_id_resolve "$payload")"
```

### commands/*.md での扱い

`commands/work.md` / `task.md` / `patch.md` / `docs-sync.md` / `git-pr.md` の Bash スニペットは、この repo の外（ユーザーの任意のプロジェクトディレクトリ）で実行されるため、このファイルを `source` せず、同じ解決式（`CLAUDE_CODE_KIT_SESSION_ID` → `CLAUDE_CODE_SESSION_ID` → `CODEX_THREAD_ID` のハッシュ）を各ファイルにインライン展開している。式を変更する場合は両方を更新すること。

## approval-safety.sh

`auto-approve-readonly.sh` と `guard-destructive-cmd.sh` の両方から `source` で読み込まれる共有 helper。

### 提供する関数

**`approval_safety_destructive_reason <command>`**

渡した Bash コマンド文字列が破壊的操作に該当するかを判定し、該当する場合は理由文字列を stdout に出力して `return 0` する。該当しない場合は何も出力せず `return 1` する。

検出対象の操作:

| パターン | 理由 |
|---|---|
| `rm -rf /` などシステムディレクトリへの再帰削除 | システムディレクトリ破壊 |
| `dd of=/dev/*` | ブロックデバイスへの直接書き込み |
| `shred /dev/*` | ブロックデバイスの破壊的消去 |
| `wipefs` | ファイルシステムシグネチャの消去 |
| `truncate -s 0 /dev/*` | ブロックデバイスのゼロ化 |
| `mkfs.*` | ファイルシステムの作成・上書き |
| `:(){ :|: & };:` などの fork bomb | プロセス爆弾 |
| `git filter-repo`, `git filter-branch` | 履歴書き換え |
| `git push --force` / `push -f` | 強制プッシュ |
| `git reset --hard` | ハードリセット |
| `git checkout -- .`, `git restore .` | 全ファイル復元（変更破棄） |
| `git clean -f` | 未追跡ファイルの強制削除 |
| `git branch -D` | ブランチの強制削除 |
| `git stash drop`, `git stash clear` | stash の削除 |

### 使い方（hook から呼び出す例）

```bash
# hook script 内で source する
. "${REPO_DIR}/hooks/lib/approval-safety.sh"

# コマンドが破壊的か判定する
reason=$(approval_safety_destructive_reason "$command")
if [ -n "$reason" ]; then
    # JSON block decision を返す
    printf '{"decision":"block","reason":"%s"}\n' "$reason"
    exit 0
fi
```
