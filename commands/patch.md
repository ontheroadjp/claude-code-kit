# /patch

このファイルは `commands/work.md` から Read されることを前提とした、docs 変更を伴わない軽微な修正専用のワークフローです。ゲート確認・ルーティング判定・stash 管理は work.md が担います。

- issue 不要 / PR 不要 / docs-sync 不要
- branch + commit → ユーザーが main へマージ
- ドキュメント変更が必要になった場合は task フローへエスカレーションする

template 参照時の `TEMPLATES_DIR` は実行 agent に応じて決定する:
- Claude Code: `~/.claude/templates`
- Codex CLI: `~/.codex/templates`

---

## ワークフロー

### Phase 1: 実装

#### Step 1: 現状調査の引き継ぎと補完

- work.md の現状調査結果を引き継ぐ
- `docs/.ai/repo.profile.json` および `docs/L3_implementation/specification_summary.md` は work フェーズで既に Read 済みのため、再度 Read しない
- Step 2（プラン確認）に必要な情報が不足している場合のみ、差分を調査・補完する
- 変更対象ファイルが確定したら、各ファイルに対応する L3 per-file doc を確認し、存在する場合は必ず Read する:
    - 対応パス: `docs/L3_implementation/<変更対象ファイルのパス>.md`（例: `commands/patch.md` → `docs/L3_implementation/commands/patch.md`）
    - 存在する場合: Read して設計意図・現状仕様を把握してから Step 2 へ進む
    - 存在しない場合: スキップ（patch フローは L3 per-file doc を作成しない。docs 変更が必要になった場合は task フローへエスカレーションする）

#### Step 2: プラン確認（必須・スキップ不可）

以下を提示してユーザーの明確な許可を得る:

- 変更内容サマリ
- 利用ツール: `tool:git_write`（git add / commit / stash / checkout 等）
- 新規作成ファイル（絶対パス）
- 編集ファイル（絶対パス）

ユーザーから OK が出た場合:
    - 以下の Bash コマンドで session-approved ファイルの正確なパスを解決する（セッション ID は `$CLAUDE_CODE_SESSION_ID`（Codex は `$CODEX_THREAD_ID` のハッシュ）から直接取得し、共有ファイル経由では取得しない — 複数セッション同時実行時の混線を避けるため）:
      ```bash
      SESSION_ID="${CLAUDE_CODE_KIT_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-}}"
      if [ -z "$SESSION_ID" ] && [ -n "${CODEX_THREAD_ID:-}" ]; then
          SESSION_ID="codex-$(printf '%s' "$CODEX_THREAD_ID" | sha256sum | cut -c1-16)"
      fi
      SESSION_ID="$(printf '%s' "$SESSION_ID" | tr -c 'A-Za-z0-9._-' '_')"
      SESSION_APPROVED_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/claude-code-kit/sessions/${SESSION_ID}/session-approved"
      ```
      セッション ID が解決できない場合（hook が未実行のケース）はスキップして Step 3 へ進む。
    - Write ツールで上記で取得したパスに session-approved ファイルを作成する。内容（1行1エントリ）:
        - `tool:git_write`
        - 新規作成・編集ファイルの絶対パス（例: `file:/abs/path/to/file.md`）
    - 注: `session-approved` はこの Step で 1 度だけ書き込む。実行中にスコープを追加しようとすると hook がブロックする。スコープ変更が必要な場合はこの Step に戻り、ユーザーの許可を得てから再書き込みすること。
    - Step 3 へ進む

ユーザーから質問や変更があった場合:
    - ユーザーの質問・変更に対応する

#### Step 3: 実行

- ブランチ作成:
    ```bash
    git checkout -b patch/<変更内容を表す slug>
    ```
- ソースコードを修正する場合は、修正前に対象ファイルの言語に応じたコマンドを Read し、記載された原則を適用すること:
    - Python (.py): `commands/coding-py.md`
    - JavaScript (.js): `commands/coding-js.md`
    - TypeScript (.ts): `commands/coding-ts.md`
    - React (.jsx): `commands/coding-js.md` → `commands/coding-react.md`
    - React + TypeScript (.tsx): `commands/coding-ts.md` → `commands/coding-react.md`
    - Next.js（`next` dependencyまたはNext.js configで判定）: 上記に加えて `commands/coding-nextjs.md`
    - Shell script (.sh): `commands/coding-sh.md`
    - その他の言語: `commands/coding-general.md`
- 変更を実施する（ユーザー確認不要）
- コミットは複数回でも可。各コミットで `/git-commit` を実行する
    - パラメータ: `issue_number=none`, `allowed_types=[fix, refactor, chore, style, test, docs]`
    - 注: patch フローは新機能追加を行わないため `feat` は許可しない

---

### Phase 3: 報告

ユーザーに以下を報告する:

- 変更内容サマリ
- 必要なユーザー処理:
    ```bash
    git checkout main
    git merge --ff patch/<slug>
    git push origin main
    git branch -d patch/<slug>
    ```

報告後、`git checkout main` で main に戻る。

---

## エスカレーション（patch → task）

patch フローの前提は「軽微・局所・追跡不要」である。
Phase 2 の実行中に **この前提が崩れた** と判断した場合、task フローに引き継ぐ。

前提が崩れる典型例（これに限らず、判断の根拠として使うこと）:

- docs への追加・変更・削除が必要になった
- 変更範囲が当初想定より大幅に広がった（複数ファイル・複数機能にまたがるなど）
- 変更の影響や副作用が読み切れず、正式なレビュー・追跡が必要と判断した
- ユーザーから追加指示があり、スコープが patch の範囲を超えた

**引き継ぎ手順:**
1. 未コミット変更がある場合: `/git-commit` を実行する
    - パラメータ: `issue_number=none`, `allowed_types=[fix, refactor, chore, style, test, docs]`
2. ユーザーに報告: 「patch フローの前提（軽微・局所・追跡不要）が崩れたため task フローに切り替えます。理由: <実際のエスカレーション理由>」
3. `${TEMPLATES_DIR}/issue.md` をもとに issue のドラフトを作成する
    - 「/patch で実施済みの変更」と「追加スコープ（エスカレーション理由）」を必ず記載する
    - **issue のタイトル・本文は英語で記述する**
    - ユーザーに確認を取り、`gh issue create` で作成する
4. `commands/task.md` を Read し、Phase 1 Step 2（プラン策定）から継続する
    - ブランチは再利用する（`patch/<slug>` のまま進む）
    - ゲートは通過済みとして扱う
    - Step 1（現状調査）は完了済みとして扱う
