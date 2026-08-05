# 生成される中間ファイルとその削除

セッション中に生成される中間ファイルの保存場所・作成タイミング・削除担当をまとめる。

---

## セッション状態ファイル

### `session-approved`

**パス:**
```
${XDG_STATE_HOME:-~/.local/state}/claude-code-kit/sessions/<session-id>/session-approved
```

**作成:** `/task` Phase 1 Step 2 または `/patch` Step 2（ユーザーがプランを承認したタイミング）
**削除:**
- `hooks/cleanup-session.sh`（Stop hook）— ターン終了ごとに削除し、空になったディレクトリを `rmdir` で除去

`commands/work.md` G-0 は issue #261 以降 `session-approved` を削除・空書き込みしない。Stop hook が正常に削除した absent 状態を維持し、次の実承認内容を初回 write として扱わせるためである。

**目的:** auto-approve-readonly hook がこのファイルの内容（許可ツールカテゴリ・ファイルパス）を読み、承認済みスコープ内の操作を自動許可する。

---

## SESSION_TMP_DIR（AI agent セッション I/O 領域）

AI agent がセッション内で自由に読み書きできる汎用ディレクトリ。`session-approved` に関係なく、自セッションの `SESSION_TMP_DIR` 配下への Write / Edit は `auto-approve-readonly` hook が常に自動承認する。

### パス

```
/tmp/claude-code-kit/<session-id>/
```

`<session-id>` は command workflow が `CLAUDE_CODE_KIT_SESSION_ID`、`CLAUDE_CODE_SESSION_ID`、`CODEX_THREAD_ID` から解決する。hook payload を利用する詳細な優先順位は `hooks/lib/session-id.sh` に定義される。

### 利用例: PR 作成フロー

| ファイル | 作成 | 参照 |
|---|---|---|
| `pr-title.txt` | `/task` Phase 2 Step 1 | `/git-pr` |
| `pr-body.md` | `/task` Phase 2 Step 1 | `/docs-sync`、`/git-pr` |
| `pr-docs-sync-result.md` | `/docs-sync` Phase 3 | `/git-pr` |

### 削除

**OS の自然消去に委ねる（Stop hook では削除しない）。**

Stop hook はターン終了ごとに発火する。`/task` → `/docs-sync` → `/git-pr` のスキル連鎖中にも発火するため、Stop hook が `/tmp` を削除すると次のスキルがファイルを参照できなくなる。この問題を避けるため PR #169 で Stop hook からの削除処理を外した。

`/tmp` は OS 再起動または `tmpfiles.d` の設定により自動的に消去される。

---

## AI agent 一時ファイルのベストプラクティス

### Claude Code のセキュリティチェックが引っかかるパターン

**パターン 1: `python3 -c` 内での `subprocess.run()`**

```bash
# これは止まる（ネスト subprocess 検出）
python3 -c "
import subprocess
subprocess.run(['python3', 'script.py', ...])
"
```

`python3 -c "..."` の中でさらに `subprocess.run()` を呼ぶと、Claude Code が「コードがコードを起動する」パターンを検出して確認を求める。auto-approve では回避できない。

**パターン 2: `gh --body` に `\n#` を含む**

```bash
# これは止まる（\n# パターン検出）
gh issue comment 123 --body "## タイトル
### サブタイトル"
```

改行 + `#` が引数内にあると、シェルの引数検証で `#` 以降がコメントとして扱われる可能性があるとして Claude Code が確認を求める。

### 対処法: セッション `/tmp` にファイルを書いて実行

```bash
# スクリプトをセッション tmp に書いて直接実行
cat > /tmp/claude-code-kit/${SESSION_ID}/test_script.py << 'EOF'
import tempfile, pathlib, subprocess
# ... テストコード ...
EOF
python3 /tmp/claude-code-kit/${SESSION_ID}/test_script.py
```

```bash
# gh コメントも --body-file で回避
cat > /tmp/claude-code-kit/${SESSION_ID}/comment.md << 'EOF'
## 実装完了
### 変更内容
...
EOF
gh issue comment 123 --body-file /tmp/claude-code-kit/${SESSION_ID}/comment.md
```

**利点:**
- ネスト subprocess 検出・`\n#` 検出の両方を回避できる
- `CLAUDE.md` で定めたセッション tmp ディレクトリのルールに沿っている
- Stop hook の発火タイミングに関わらず、OS の自然消去に任せられる

根拠: `hooks/cleanup-session.sh:15-24`, `hooks/lib/session-id.sh:17-46`, `commands/task.md`, `commands/patch.md`, `commands/git-pr.md`
