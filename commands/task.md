# /task

このファイルは `commands/work.md` から Read されることを前提とした、docs 変更を伴う実装専用のワークフローです。ゲート確認・ルーティング判定・stash 管理は work.md が担います。

- 想像・憶測は一切禁止
- すべての判断は docs/.ai/repo.profile.json および docs の記述に基づく
- **docs/* の変更は原則行わない** — ドキュメント同期は /docs-sync が担う。ただし L3 per-file doc（`docs/L3_implementation/<source-path>.md`）は実装フローの一部として Step 3.2 で作成・更新する
- 全ての作業は issue と紐づく（issue がない場合は自動生成する）
- ワークフローは 3 フェーズで構成される

template 参照時の `TEMPLATES_DIR` は実行 agent に応じて決定する:
- Claude Code: `~/.claude/templates`
- Codex CLI: `~/.codex/templates`

```
Phase 1: 実装（コード変更を完結させる）
Phase 2: PR 本文の準備 → /docs-sync 自動実行 → /git-pr 自動実行
Phase 3: 最終報告
```

フェーズをまたいで遡ることはない（フェーズ内の Step を遡ることは許容）。

## ソースコード修正時の注意点
ソースコードを修正する場合は、修正前に対象ファイルの言語に応じたコマンドを Read し、記載された原則を適用すること:
- Python (.py): `commands/coding-py.md`
- JavaScript (.js / .jsx): `commands/coding-js.md`
- TypeScript (.ts / .tsx): `commands/coding-ts.md`
- その他の言語: `commands/coding-general.md`

---

## ワークフロー

### Phase 1: 実装

#### Step 0: issue の確認（必須）

- /patch からのエスカレーションの場合:
    - patch.md 側で issue が作成済みのため、その issue 番号を引き継ぐ
    - `gh issue view <番号> --json title,body` で内容を確認する
    - Step 1 はスキップして Step 2 へ進む

- ユーザーが issue 番号を伝えた場合（`/work #N` 形式を含む）:
    - `commands/new-issue.md` は Read しない
    - `gh issue view <番号> --json title,body` で内容を確認する
    - 以降その issue を作業の起点とする

- issue 番号が伝えられていない場合:
    - issue は Step 2 のプラン確定・ユーザー承認後に自動作成する
    - ここでは何もせず Step 1 へ進む

以降、全てのコミットメッセージに `#<issue番号>` を含める。

#### Step 1: 現状調査の引き継ぎと補完

- work.md の現状調査結果を引き継ぐ
- `docs/.ai/repo.profile.json` および `docs/L3_implementation/specification_summary.md` は work フェーズで既に Read 済みのため、再度 Read しない
- Step 2（プラン策定）に必要な情報が不足している場合のみ、差分を調査・補完する
- 未確認事項が残る場合はユーザーに報告し、確定するまで Step 2 に進まない
- 変更対象ファイルが確定したら、各ファイルに対応する L3 per-file doc を確認し、存在する場合は必ず Read する:
    - 対応パス: `docs/L3_implementation/<変更対象ファイルのパス>.md`（例: `commands/task.md` → `docs/L3_implementation/commands/task.md`）
    - L3 per-file doc はファイルの現状スナップショットと設計意図を記録したもの
    - 存在する場合: Read して設計意図・現状仕様を把握してから Step 2 へ進む
    - 存在しない場合: スキップ（Step 3.2 で新規作成する）

※ 事実が確定できない場合、ユーザーに理由を報告し、提案を提示して判断を仰ぐ

#### Step 2: プラン策定（必須・スキップ不可）
以下を含む作業プランを確定する:

- 完了条件
- 変更前 / 変更後の状態（Before / After）
- 変更対象（最小単位）
- 想定される影響とリスク
- 検証方法（成功条件）
- ロールバック方針
- 利用ツール（該当するものを列挙）:
    - `tool:git_write`（git add / commit / push / stash / checkout / switch / branch / merge）
    - `tool:gh_issue_write`（gh issue create / edit / close / comment / reopen）
    - `tool:gh_pr_write`（gh pr create / edit / merge / close / ready）
- 新規作成ファイル（絶対パス）
- 編集ファイル（絶対パス）
- タスクリスト（以下を必ず含む）
    - 作業ブランチの作成（feat/change/fix/test/chore-<slug>）
        - /patch からのエスカレーションの場合はブランチ再利用（新規作成しない）
    - 実行手順（順序付き）
    - テストケースの作成/更新
    - テストの実行

※ Step 3 実行前に調査結果・作業プランをユーザーに提示し、明確な許可を得ること（必須）

ユーザーから OK が出た場合:
    - 以下の Bash コマンドで session-approved ファイルの正確なパスを取得する:
      ```bash
      cat "${XDG_STATE_HOME:-$HOME/.local/state}/claude-code-kit/current-session-approved-path"
      ```
      ファイルが存在しない場合（hook が未実行のケース）はスキップして Step 3 へ進む。
    - Write ツールで上記で取得したパスに session-approved ファイルを作成する。内容（1行1エントリ）:
        - 利用ツールカテゴリ（例: `tool:git_write`）
        - 新規作成・編集ファイルの絶対パス（例: `file:/abs/path/to/file.md`）
        - Step 3.2 で作成・更新する L3 per-file doc の絶対パス（例: `file:/abs/path/to/docs/L3_implementation/commands/task.md`）
    - 注: `session-approved` はこの Step で 1 度だけ書き込む。実行中にスコープを追加しようとすると hook がブロックする。スコープ変更が必要な場合はこの Step に戻り、ユーザーの許可を得てから再書き込みすること。
    - **issue が未作成の場合**（Step 0 で issue 番号がなかった場合）:
        - `commands/new-issue.md` を Read し、**Step 4〜Step 5 のみ**実行して issue を作成する
            - Step 1〜3（アイデア捕捉・明確化・スコープ判定）はスキップする（確定済みプランの内容で代替）
            - Step 4 のドラフトは作業プランの内容（完了条件・背景・変更対象・検証方法）を `${TEMPLATES_DIR}/issue.md` の各セクションに英語で埋めて作成する
            - Step 6（引き継ぎ案内）はスキップする
            - **issue 内容のユーザー確認は行わない**（プラン承認で確定済みのため）
        - 作成した issue 番号を以降の起点とする
    - **issue が作成済みの場合**（ユーザーから issue 番号を受け取っていた場合）:
        - 調査結果・作業プランを対象 issue の本文に追記する
    - Step 3 へ進む

ユーザーから質問や変更があった場合:
    - ユーザーの質問・変更に対応する

#### Step 3: 実行
3.1 作業プランに従って実装を行う
3.2 実装完了後:
    - 作業内容をユーザーに報告
    - ユーザーに実機テストおよびコードレビューを促して待機
    - ユーザーから追加指示が出た場合:
        - Step 2（必要に応じて Step 1）へ戻る
        - ゲートは通過済みの前提で作業を続ける
    - ユーザーから OK が出た場合:
        - 変更した各ソースファイルに対応する L3 per-file doc を作成または更新する:
            - パス: `docs/L3_implementation/<変更したファイルのパス>.md`（例: `commands/task.md` → `docs/L3_implementation/commands/task.md`）
            - 内容: **現時点のスナップショット**（changelogや作業履歴ではない）
                - 目的・役割
                - 動作の概要と主要な判定ロジック・フロー
                - 重要な設計判断とその理由（なぜそうしたか — 非自明な選択に限る）
                - 統合ポイント（呼び出し元・呼び出し先）
                - 注意事項・既知の制限
            - 過去の経緯は「なぜ現在の設計になっているか」を説明する場合にのみ含める
            - 根拠コードへの参照を含める（例: `commands/task.md:42-100`）
        - `/git-commit` を実行する
            - パラメータ: `issue_number=<Step 0 で確定した issue 番号>`, `allowed_types=[feat, fix, refactor, chore, style, test, docs]`
        - 作業内容を対象 issue のコメントとして投稿する
        - ユーザー確認なしに即座に Phase 2 へ進む

---

### Phase 2: PR 本文の準備

ガード:
- main ブランチ以外にいること
- `git log main..HEAD --oneline` の出力が 1 件以上あること（実装コミットが存在すること）
- ワークスペースがクリーンであること
    - クリーンでない場合: `git stash push -m "task-phase2: auto stash"` で退避してから進む

#### Step 1. PR 本文・タイトルの準備

セッション temp ディレクトリを特定する:
```bash
APPROVED_PATH=$(cat "${XDG_STATE_HOME:-$HOME/.local/state}/claude-code-kit/current-session-approved-path" 2>/dev/null)
SESSION_ID=$(basename "$(dirname "$APPROVED_PATH")" 2>/dev/null)
SESSION_TMP_DIR="/tmp/claude-code-kit/${SESSION_ID}"
mkdir -p "$SESSION_TMP_DIR"
```

- `${TEMPLATES_DIR}/pr.md` をもとに PR 本文を作成する
- **PR のタイトル・本文は英語で記述する**
- 以下のファイルを SESSION_TMP_DIR に書き出す:
    - `${SESSION_TMP_DIR}/pr-title.txt`: PR タイトル（形式: `#<issue番号> <英語タイトル>`）
    - `${SESSION_TMP_DIR}/pr-body.md`: PR 本文（テンプレートを実際の値で埋めたもの）

ユーザーに確認する:
**「追加の変更はありますか？」**
- あり → Phase 1 Step 3 に戻って実装・コミットする（push 前のため commit 操作は自由）
- なし → `/docs-sync` を自動実行し、完了後にユーザー確認なしで即座に `/git-pr` を自動実行する

`/docs-sync` が HARD STOP した場合はそこで処理が止まり、ユーザーへ報告される（`/git-pr` は実行しない）。
`/docs-sync` 完了後、ユーザー確認なしに即座に `/git-pr` を実行する（push → PR 作成まで完結）。
Phase 3 へ進む。

---

### Phase 3: 最終報告

A. 実装したファイル（テストを除く）
B. 作成/更新したテスト
C. テストの実行結果
D. issue URL
E. PR URL（/git-pr により公開済み）
