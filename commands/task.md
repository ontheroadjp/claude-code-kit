# /task

このファイルは `commands/work.md` から Read されることを前提とした、docs 変更を伴う issue-specific implementation workflow です。通常の単一 issue と、`/task-manager` が起動する delegated worker は同じ実装契約を使います。ゲート確認・project-wide context・stash 管理は work.md が担います。

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

## 実行モード

## Work-run event contract

`/work` または `/task-manager` から `work_run_id` が渡されている場合だけ、実行 agent 用 installed `work-run-events.sh` に semantic event を best-effort で渡す。helper の失敗は無視し、実装・approval・PR creation の結果を変更しない。自由記述や成果物本文は渡さない。

- plan 提示時: `issue_state_changed issue_number=<N> state=awaiting_plan_approval`
- plan 承認後: `issue_state_changed issue_number=<N> state=implementing`
- 実装レビュー待ち: `approval_wait_started issue_number=<N> approval_kind=implementation`
- 実装 OK/NG: 対応する `approval_wait_finished` (`outcome=approved|rejected`)
- Ready PR 作成後: `issue_state_changed issue_number=<N> state=awaiting_pr_approval`

ordinary mode では親 `/work` と同じ session context を読む。delegated mode では worker lifecycle の `attach` 済み context を読む。

### 通常モード

`/work` が単一 issue / 単一作業として委譲する。既存のユーザー gate をこの会話で直接扱い、Ready PR 作成後に終了する。

### delegated worker mode

`/work` → `/task-manager` が起動した issue worker として実行する。payload には accepted issue metadata、isolated worktree/branch、base SHA、merge order、complete project-wide context が必要である。

- `/work` の preflight、repository profile、README、primary investigation doc、workspace/stash gate を再実行しない。
- handed-off evidence は routine reread しない。`missing evidence`、`stale evidence`、`base drift` を path・範囲・理由つきで記録した場合だけ shortest-path supplemental investigation を行う。
- Step 2 の plan を `/task-manager` へ返し `awaiting_plan_approval` で待つ。approval は対象 issue だけに適用する。
- approval 後は同じ worker が Step 3、tests、L3 per-file docs、Phase 2、`/docs-sync`、`/git-pr` まで継続する。
- `/git-pr` には Ready PR を作成させる。Draft PR で停止しない。
- Ready PR handoff を `/task-manager` へ返して `awaiting_pr_approval` で待ち、自分では merge・parent cleanup・stash restoration を行わない。
- replacement worker は approved plan と既存 evidence/state を引き継ぐ。

## ソースコード修正時の注意点
ソースコードを修正する場合は、修正前に対象ファイルの言語に応じたコマンドを Read し、記載された原則を適用すること:
- Python (.py): `commands/coding-py.md`
- JavaScript (.js): `commands/coding-js.md`
- TypeScript (.ts): `commands/coding-ts.md`
- React (.jsx): `commands/coding-js.md` → `commands/coding-react.md`
- React + TypeScript (.tsx): `commands/coding-ts.md` → `commands/coding-react.md`
- Next.js（`next` dependencyまたはNext.js configで判定）: 上記に加えて `commands/coding-nextjs.md`
- Shell script (.sh): `commands/coding-sh.md`
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
- delegated worker mode では project-wide handoff を引き継ぎ、issue-specific な不足だけを補完する。再読理由と supplemental evidence を plan に記録する
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
- 利用ツール:
    - `tool:git_write`（git add / commit / push / stash / checkout / switch / branch / merge） — 該当する場合のみ列挙
    - `tool:gh_issue_write:<N>`（gh issue create / edit / close / comment / reopen。`create` は対象番号を持たないため N に関わらず常に承認され、それ以外の verb は対象 issue 番号が N と一致する場合のみ承認される） — **`/task` フローでは常に列挙する（条件判定不要）**。Step 3.2 で issue が新規・既存いずれの場合も完了コメントを投稿するため、issue の有無に関わらず必ず必要になる。N は対象 issue 番号（後述の順序に従い確定させる）
    - `tool:gh_pr_write:<N>`（gh pr create / edit / merge / close / ready。`create` は対象番号を持たないため N に関わらず常に承認される） — 該当する場合のみ列挙。Phase 2 で `/git-pr` が `gh pr create` を呼ぶため実質的に毎回該当する。この時点では PR はまだ存在せず対象 PR 番号もないため、N には対象 issue 番号をそのまま流用する（`create` は N を検査しないため形式的な値で構わない）
- 新規作成ファイル（絶対パス）— プラン本文で言及した実装ファイル・テストファイルを漏れなく転記する
- 編集ファイル（絶対パス）— 同上
- タスクリスト（以下を必ず含む）
    - 作業ブランチの作成（feat/change/fix/test/chore-<slug>）
        - /patch からのエスカレーションの場合はブランチ再利用（新規作成しない）
    - 実行手順（順序付き）
    - テストケースの作成/更新
    - テストの実行

※ Step 3 実行前に調査結果・作業プランをユーザーに提示し、明確な許可を得ること（必須）。delegated worker mode は `/task-manager` に plan を返し、同 workflow が issue-specific approval を relay する

ユーザーから OK が出た場合、`tool:gh_issue_write:<N>` に使う N（対象 issue 番号）を session-approved 書き込み前に確定させる必要があるため（issue #297: 番号スコープ化に伴い、書き込みより後に番号が判明する順序は成立しない）、以下の順序で進める:
    - **issue が未作成の場合**（Step 0 で issue 番号がなかった場合）:
        - `commands/new-issue.md` を Read し、**Step 4〜Step 5 のみ**実行して issue を作成する
            - Step 1〜3（アイデア捕捉・明確化・スコープ判定）はスキップする（確定済みプランの内容で代替）
            - Step 4 のドラフトは作業プランの内容（完了条件・背景・変更対象・検証方法）を `${TEMPLATES_DIR}/issue.md` の各セクションに英語で埋めて作成する
            - Step 6（引き継ぎ案内）はスキップする
            - **issue 内容のユーザー確認は行わない**（プラン承認で確定済みのため）
        - 作成した issue 番号を以降の起点（N）とする
        - 注: この `gh issue create` 呼び出しの時点では session-approved がまだ存在しないため、通常の確認プロンプトに従う（1 回限り。番号スコープ化のトレードオフ）
    - **issue が作成済みの場合**（ユーザーから issue 番号を受け取っていた場合）: Step 0 で確定した issue 番号を N とする
    - 以下の Bash コマンドで session-approved ファイルの正確なパスを解決する（`hooks/lib/session-paths.sh` が `hooks/lib/session-id.sh` の `session_id_resolve` を再利用して1行で絶対パスを返す。共有ファイル経由では取得しない — 複数セッション同時実行時の混線を避けるため。brace expansion や代入への command substitution をコマンド自体に含めないことで worktree 隔離セッションでの harness 拒否を避ける、issue #316）:
        - Claude Code: `bash ~/.claude/hooks/lib/session-paths.sh session-approved`
        - Codex CLI: `bash ~/.codex/hooks/lib/session-paths.sh session-approved`

      出力された1行の絶対パスを以降 `SESSION_APPROVED_FILE` として扱う。コマンドが失敗した場合（hook が未実行でセッション ID が解決できないケース）はスキップして Step 3 へ進む。
    - Write ツールで上記で取得したパスに session-approved ファイルを作成する。内容（1行1エントリ）:
        - 利用ツールカテゴリ（例: `tool:git_write`、`tool:gh_issue_write:<N>`、該当する場合は `tool:gh_pr_write:<N>`。N は上記で確定した issue 番号）
        - 新規作成・編集ファイルの絶対パス（例: `file:/abs/path/to/file.md`）
        - Step 3.2 で作成・更新する L3 per-file doc の絶対パス（例: `file:/abs/path/to/docs/L3_implementation/commands/task.md`）
    - 注: `session-approved` はこの Step で 1 度だけ書き込む。実行中にスコープを追加しようとすると hook がブロックする。スコープ変更が必要な場合はこの Step に戻り、ユーザーの許可を得てから再書き込みすること。
    - **issue が元から作成済みだった場合のみ**: 調査結果・作業プランを対象 issue の本文に追記する（`gh issue comment <N>` は上記で書き込んだ `tool:gh_issue_write:<N>` により自動承認される）。今回新規作成した場合は Step 4 のドラフトが既に内容を含むため追記不要
    - 通常モードでは approved plan の作業ブランチを作成または切り替える。delegated worker mode では payload の isolated worktree/branch が既に用意されているため再作成しない
    - 作業ブランチ切替後、Claude Code だけが Git の返した branch name を使い、`/rename <作業ブランチ名>` と同じ結果になるよう更新する。Codex CLI はスキップし、失敗しても実装を止めない:
      ```bash
      branch_name=$(git branch --show-current)
      bash ~/.claude/scripts/rename-thread.sh "$branch_name" || true
      ```
    - Step 3 へ進む

ユーザーから質問や変更があった場合:
    - ユーザーの質問・変更に対応する

#### Step 3: 実行
3.1 作業プランに従って実装を行う

3.2 実装完了後:
    - 作業内容をユーザーに報告（delegated worker mode は `/task-manager` へ implementation result を返す）
    - ユーザーに実機テストおよびコードレビューを促して待機（delegated worker mode は `/task-manager` が gate を relay する）
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
    - Claude Code では `bash ~/.claude/scripts/worktree-status.sh`、Codex CLI では `bash ~/.codex/scripts/worktree-status.sh` の出力を使用する。ヘルパーは worktree 隔離セッションの current session manifest に記録された自己作成 symlink（完全一致または親ディレクトリ一致）のみを自動除外し、それ以外の差分はそのまま返す
    - 除外後もクリーンでない場合: `git stash push -m "task-phase2: auto stash"` で退避してから進む

#### Step 1. PR 本文・タイトルの準備

セッション temp ディレクトリを特定する（`hooks/lib/session-paths.sh` が `hooks/lib/session-id.sh` の `session_id_resolve` を再利用して1行で絶対パスを返す）。`mkdir -p` の対象に変数参照を残すと `hooks/auto-approve-readonly.sh` が静的判定できず確認プロンプトに落ちるため、また brace expansion や代入への command substitution を含む解決ステップ自体が worktree 隔離セッションで harness に拒否されるため（issue #316）、CLAUDE.md の resolve-then-embed 規約に従い、解決ステップとリテラル値埋め込みを別の Bash 呼び出しに分ける。

解決ステップ（read-only）:
- Claude Code: `bash ~/.claude/hooks/lib/session-paths.sh session-tmp-dir`
- Codex CLI: `bash ~/.codex/hooks/lib/session-paths.sh session-tmp-dir`

出力された絶対パスを以降 `SESSION_TMP_DIR` として使用する。実行ステップでは変数ではなくリテラル文字列として埋め込む:
```bash
mkdir -p "<上記で得た絶対パス>"
```

- `${TEMPLATES_DIR}/pr.md` をもとに PR 本文を作成する
- **PR のタイトル・本文は英語で記述する**
- PR タイトルの Conventional Commit type は PR 全体の主目的に基づき `feat` / `fix` / `refactor` / `chore` / `style` / `test` / `docs` から選び、primary implementation commit と同じ type にする
- PR タイトルの description は PR 全体の目的を英語で簡潔に表し、primary implementation commit の目的と整合させる
- PR に含まれる commit が 1 件か複数かにかかわらず、同じ PR タイトル形式を使用する
- `Specific docs sections to update` フィールドには、Phase 1 Step 1 の投資調査で `docs/L3_implementation/specification_summary.md` を読んだ際に確認済みのセクション見出し（`###`）の行範囲を `docs/L3_implementation/specification_summary.md:<line-range>` の citation 形式で書く（再度 Read して探し直さない）。対象箇所が複数ある場合は複数行に列挙する。投資調査でこの specification_summary.md セクションを特定していない場合のみ、ファイル名や説明文で代替する
- 以下のファイルを SESSION_TMP_DIR に書き出す:
    - `${SESSION_TMP_DIR}/pr-title.txt`: PR タイトル（形式: `<type>(#<issue番号>): <英語 description>`）
    - `${SESSION_TMP_DIR}/pr-body.md`: PR 本文（テンプレートを実際の値で埋めたもの）

ユーザーに確認する:
**「追加の変更はありますか？」**
- あり → Phase 1 Step 3 に戻って実装・コミットする（push 前のため commit 操作は自由）
- なし → `/docs-sync` を自動実行し、完了後にユーザー確認なしで即座に `/git-pr` を自動実行する

`/docs-sync` が HARD STOP した場合はそこで処理が止まり、ユーザーへ報告される（`/git-pr` は実行しない）。
`/docs-sync` 完了後、ユーザー確認なしに即座に `/git-pr` を実行する（push → PR 作成まで完結）。
Phase 3 へ進む。

delegated worker mode では Ready PR 作成後、issue number、approved plan、branch/worktree、base/head SHA、PR number/URL、changed source/test/docs、observable changes、design decisions、tests、risks/followups を implementation handoff として `/task-manager` へ返し、merge せず待機する。

---

### Phase 3: 最終報告

A. 実装したファイル（テストを除く）
B. 作成/更新したテスト
C. テストの実行結果
D. issue URL
E. PR URL（/git-pr により公開済み）

`/task` フローのゴールはここで完結する ready PR の作成までである。PR に対する追加レビューや main への merge は自動実行せず、人間（または `/review-resolve`・`/codex-review` を手動起動するユーザー）が行う。
