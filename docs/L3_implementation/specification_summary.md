# Specification Summary

## 対象

このサマリは、`commands/`、`skills/`、`hooks/`、`templates/`、`site/`、CI の現在の実体を、確認できた範囲で整理する。

根拠: `rg --files -uu -g '!.git/**'`, `docs/.ai/repo.profile.json`

## Command Specifications

### `/work` (`commands/work.md`)

全作業の通常入口。G-0 で main へ checkout し、現在の hook セッションに対応する session-approved を削除して前回の承認状態をクリアする。その後 repo profile と workspace を確認する。issue 番号がある場合は現状調査より先に labels を取得する。

exact `report` label があれば `commands/report-review.md` へ委譲して実装せず終了する。それ以外は issue 起点か、次に docs 変更が必要かで task / patch を判定する。

非 main ブランチからの再開（case B scenario 2: コミットあり・ワークスペースクリーン）では、Phase 2 直接開始ではなく Phase 1 Step 2 から開始し session-approved を再作成する。

根拠: `commands/work.md:7-143`

### `/report-review` (`commands/report-review.md`)

`report` label の issue 専用 read-only workflow。issue context と必要な repository evidence を読み、Facts、Assessment、Opinions、Proposals、Risks and Unknowns を分離して標準出力に提示する。ファイル、Git state、GitHub issue / PR を変更せず、実装 workflow へ委譲しない。

根拠: `commands/report-review.md:1-91`

### `/task` (`commands/task.md`)

`/work` から呼ばれる docs 変更を伴う実装 flow。issue がなければプラン策定とユーザー許可を先に行い、承認後に `commands/new-issue.md` Step 4-5 を使ってユーザー確認なしで issue を自動作成する（Step 1-3 の対話はスキップし、確定済みプランの内容で各セクションを埋める）。Step 1 では変更対象ファイルが確定した後に対応する L3 per-file doc（`docs/L3_implementation/<source-path>.md`）が存在する場合は必ず Read する。Step 2 では L3 per-file doc のパスを session-approved に含める。実装後・`/git-commit` 前に変更した各ソースファイルの L3 per-file doc を作成または更新し（現状スナップショット + 設計意図、changelog ではない）、`/git-commit` で commit する。Phase 2 では PR 本文・タイトルを SESSION_TMP_DIR（`/tmp/claude-code-kit/<session-id>/`）の `pr-body.md` / `pr-title.txt` に書き出し、`/docs-sync` → `/git-pr` を順に自動実行する（push・PR 作成は `/git-pr` が担う）。`docs/*` の変更は原則行わないが、L3 per-file doc（`docs/L3_implementation/<source-path>.md`）は実装フローの一部として例外的に task が管理する。

根拠: `commands/task.md:1-15`, `commands/task.md:50-66`, `commands/task.md:94-95`, `commands/task.md:139-170`

### `/patch` (`commands/patch.md`)

`/work` から呼ばれる docs 変更不要の軽微修正 flow。Step 1 では変更対象ファイルが確定した後に対応する L3 per-file doc（`docs/L3_implementation/<source-path>.md`）が存在する場合は Read する（L3 per-file doc は作成しない — docs 変更が必要になった場合は task フローへエスカレーションする）。プラン確認後に `patch/<slug>` branch で変更・commit し、ユーザーへ fast-forward merge 手順を報告する。前提が崩れた場合は issue draft を作り task flow へ移行する。

根拠: `commands/patch.md:1-95`, `commands/patch.md:15-26`

### `/docs-sync` (`commands/docs-sync.md`)

PR branch 上で `git diff main...HEAD` を事実として docs と README を最小更新する。G-4（PR 存在確認）は廃止。補助情報は GitHub PR body の代わりに SESSION_TMP_DIR の `pr-body.md` から取得する（存在しない場合は git diff のみで判断）。HARD STOP 判定、更新、commit、`pr-docs-sync-result.md` 書き出しを行う。push・PR 作成は行わない（`/git-pr` が担う）。L0 は通常更新しない。4 フェーズ構成（Phase 4 は最終報告）。

Phase 3 では docs・README.md 更新に加え、L3 per-file doc の変更履歴セクションを自動更新する。`git diff --name-only` で取得したソースファイル（`docs/` 配下を除く）に対応する `docs/L3_implementation/<path>.md` が存在する場合、`git log --oneline -10 -- <file>` を実行し `## 変更履歴（git log より自動生成）` セクションを更新または末尾追加する。L3 doc が存在しないファイルはスキップ（L3 doc 新規作成は `/task` が担う）。

根拠: `commands/docs-sync.md:1-175`

### `/init-docs` (`commands/init-docs.md`)

G-2 で `docs/init-docs-<YYYYMMDD>` 作業ブランチを作成または切り替え、そのブランチ上で repo 再観測、local tooling 観測、`docs/.ai/repo.profile.json` 生成、L0-L3 docs 生成、整合性検証、README scaffold 確認、CLAUDE.md / AGENTS.md 更新を行う。Phase 7 はユーザー確認後に作業ブランチ確認、commit、draft PR 作成を行う。

local tooling 観測では `gh`、`node`、`npm`、Node.js runtime manager hints を確認し、環境依存の注意を command workflow ではなく `CLAUDE.md` の `Local Tooling Environment` に出力する。`AGENTS.md` は原則として `CLAUDE.md` への symlink とし、Codex CLI も同じ AI 運用情報を読む。

根拠: `commands/init-docs.md:21-47`, `commands/init-docs.md:303-319`, `commands/init-docs.md:346-369`

### `/triage-issues` (`commands/triage-issues.md`)

open issue が溜まったタイミングで実行するスタンドアロンのトリアージ入口。`gh issue list` で全 open issue を取得し、`docs/.ai/repo.profile.json` および `docs/L3_implementation/specification_summary.md` と照合して stale / inconsistent / duplicated / unclear / ready の 5 カテゴリに分類する。分類結果をユーザーに提示し、issue ごとに推奨アクション（close / comment / edit / label / skip）を「理由 + 推奨アクション」付きで提示してユーザー承認後のみ実行する。`/work`・`/task`・`/new-issue`・`/review-resolve` とは独立しており、既存コマンドの振る舞いは変更しない。

根拠: `commands/triage-issues.md:1-187`

### `/new-issue` (`commands/new-issue.md`)

実装を伴わず、rough idea から issue draft を作成して `gh issue create` する任意 pre-`/work` flow。scope 分割はユーザー選択必須で、issue 本文は `~/.config/claude-code-kit/templates/issue.md` を使う。

根拠: `commands/new-issue.md:1-129`

### `/review-resolve` (`commands/review-resolve.md`)

PR 番号を受け取り、PR branch に checkout し、inline review comment・CHANGES_REQUESTED/COMMENTED/APPROVED 状態の review body comment を取得する。いずれも存在しない場合は「レビューコメントはありません」と報告して終了する。コメントごとにユーザーが対応・反対返信・理由返信・skip を選び、対応する場合は実装・commit・push・返信まで行う。

根拠: `commands/review-resolve.md:1-177`

### `/codex-review` (`commands/codex-review.md`)

PR 番号を受け取り、PR ブランチに checkout し、`codex review --base <base>` でレビューを実行する。結果を一時ファイルに保存して ANSI コードを除去し、内容を判定して問題なし / 問題ありを決定する。`CODEX_REVIEW_TOKEN` 環境変数は必須で、未設定の場合は `~/.claude/settings.local.json` への設定方法を案内してエラー終了する。設定されている場合は `gh pr review --approve` または `--request-changes` を提出する。問題ありの場合は完了報告後に `/review-resolve #<PR番号>` を自動実行する。

根拠: `commands/codex-review.md:1-155`

### `/pr-review` (`commands/pr-review.md`)

PR 番号を受け取り、実装元が Claude なら Codex、Codex なら Claude を read-only reviewer として起動する。各ラウンドで最新 `headRefOid` を固定し、reviewer 出力・GitHub review の `commit_id`・現在 HEAD が同じ SHA の場合だけ APPROVED とする。blocking finding は元 agent が session-approved 内で検証・修正し、最大3ラウンド再レビューする。`AI_REVIEW_TOKEN`（または互換 fallback の `CODEX_REVIEW_TOKEN`）は PR author と異なる GitHub account でなければならない。merge、branch 削除、main checkout/pull は行わず、人間の merge 待ちで終了する。

根拠: `commands/pr-review.md:1-190`

### `/coding-*` (`commands/coding-*.md`)

`coding-general` は言語非依存の原則を定義し、`coding-py`、`coding-js`、`coding-ts` はそれぞれ言語固有ルールを追加する。`coding-ts` は `coding-general` と `coding-js` を先に参照する。

根拠: `commands/coding-general.md:1-3`, `commands/coding-py.md:1-4`, `commands/coding-js.md:1-4`, `commands/coding-ts.md:1-12`

### `/git-commit` (`commands/git-commit.md`)

コミット作成手順を定義するスラッシュコマンド。WIP commits の正規化（HEAD が `wip:` の場合のみ、最近の non-WIP commit まで遡り `git reset --soft` で staging area に展開。non-WIP commits には一切触れない）、staged diff 取得、個人情報等のチェック、Conventional Commits message 作成、commit 実行を定義する。`task.md`・`patch.md`・`review-resolve.md`・`docs-sync.md` から `/git-commit` として呼び出される。

根拠: `commands/git-commit.md:1-109`

### `/git-pr` (`commands/git-pr.md`)

`git push` と `gh pr create` を担うスラッシュコマンド。`/task` Phase 2 から `/docs-sync` 完了後に自動呼び出しされる。SESSION_TMP_DIR（`/tmp/claude-code-kit/<session-id>/`）の `pr-title.txt`（タイトル）・`pr-body.md`（本文）・`pr-docs-sync-result.md`（docs sync 結果）を参照し、存在しない場合は git diff / テンプレートから生成する。PR は ready for review として直接作成し、作成成功後だけ PR 番号を `/pr-review` へ自動で引き継ぐ。Step 1〜7 の既存 PR 作成手順は変更せず、review handoff は Step 8 に分離されている。

根拠: `commands/git-pr.md:1-73`

## Skills

`skills/*/SKILL.md` は Codex 用の wrapper で、対応する `commands/*.md` を Source of Truth として読む。`coding-py` / `coding-js` / `coding-ts` は general など依存する command も読む構造を持つ。現存する skill wrapper は17件で、commands と対応する。`report-review` skill は read-only 境界、`pr-review` skill は merge・branch 削除・main 同期を人間管理に残す境界を保持する。

根拠: `skills/init-docs/SKILL.md:1-14`, `skills/report-review/SKILL.md`, `skills/pr-review/SKILL.md`, `skills/` 実体一覧

## Hooks

### `hooks/auto-approve-readonly.sh`

PreToolUse hook。Read、session temp / session-listed file、read-only Bash、session-approved tool category を自動承認する。Write / Edit / apply_patch は working repo（Claude/Codex 起動時の PWD が属する git リポジトリ）内であれば WIP commit 後に承認する動的防御を持つ。Bash は session-approved fast path → repo 内 rm -rf 動的防御 → destructive guard → write redirect → quote-aware segment 分割 → read-only 判定の順で評価し、分類不能な構文や write mode は通常許可フローへ戻す。`$()` は中身を再帰的に `is_safe_segment` で検証し、全て read-only であれば承認する（backtick と `<()` は常時ブロック）。詳細な許可順序・対象・除外条件は[auto-approve-readonly hook specification](https://github.com/ontheroadjp/core-toolkit-for-claude/blob/main/docs/L3_implementation/hooks/auto_approve_readonly.md)を参照する。decision log は `agent=claude|codex` と `session=<id|n/a>` を含む。

根拠: `hooks/auto-approve-readonly.sh:23-755`, `hooks/lib/approval-safety.sh:1-87`, `docs/L3_implementation/hooks/auto_approve_readonly.md`

### `hooks/lib/approval-safety.sh`

PreToolUse hook で共有する Bash safety helper。system directory 破壊、block device 操作、fork bomb、history rewrite、force push、hard reset、checkout/restore dot、clean、branch -D、stash drop/clear を破壊的操作として検出し、JSON block decision を生成する。

根拠: `hooks/lib/approval-safety.sh:1-87`

### `hooks/guard-destructive-cmd.sh`

PreToolUse Bash guard の互換 wrapper。Bash 以外は何も出力せず終了する。Bash の場合は `hooks/lib/approval-safety.sh` を読み込み、破壊的操作に該当する場合のみ JSON block decision を返す。平文 stdout は出力しない。

根拠: `hooks/guard-destructive-cmd.sh:1-25`, `hooks/lib/approval-safety.sh:1-87`

### `hooks/cleanup-session.sh`

Stop hook。現在の hook セッションに対応する `session-approved` を削除し、空になった session directory のみ削除する。SESSION_TMP_DIR（`/tmp/claude-code-kit/<session-id>/`）は削除しない。Stop hook はターン終了ごとに発火するため、スキル間（`/task` → `/docs-sync` → `/git-pr`）で temp ファイルが消えてしまう問題を避けるため。`/tmp` の自動クリーンアップ（OS 再起動 / tmpfiles.d）に委ねる。

根拠: `hooks/cleanup-session.sh:39-50`

詳細（生成される中間ファイルと削除タイミング全体）: `docs/L3_implementation/intermediate-files.md`

### `hooks/tmux-agent-status.sh`

Standalone helper called by Claude Code / Codex hooks to display AI agent status as an emoji prefix on the current tmux window title. Takes one optional argument (🔵, 🔴, or ✅); when called with no argument, enters clear mode — strips the emoji prefix and renames the window to the clean name without adding a new emoji. Silently exits when `$TMUX` is unset (no-op outside tmux). Uses `$TMUX_PANE` when available to target the current pane's window, strips repeated known status prefixes before setting the new one, and treats `tmux rename-window` failure as a silent no-op. Registered as independent entries in `install.sh` via `add_claude_hook` / `add_codex_hook`.

Semantic mapping: `UserPromptSubmit` / `PreToolUse` / `PostToolUse` → 🔵 (executing or execution resuming), `Notification` → 🔴 (permission/input needed), `Stop` → ✅ (turn complete, ready for next input). `PreToolUse` and `PostToolUse` are included so permission/input acknowledgements that do not emit `UserPromptSubmit` can still return the tmux prefix to executing state. When the claude/codex process itself exits, the shell wrapper calls the script with no argument to clear the prefix entirely:
```bash
claude() { command claude "$@"; bash ~/.claude/hooks/tmux-agent-status.sh 2>/dev/null; }
codex()  { command codex  "$@"; bash ~/.claude/hooks/tmux-agent-status.sh 2>/dev/null; }
```

根拠: `hooks/tmux-agent-status.sh:1-35`, `install.sh:155-187`

### `hooks/notify-slack.sh`

Notification と Stop で Claude/Codex の hook 設定から呼ばれる Slack 通知 script。installer は top-level hooks の symlink と event registration を両環境へ追加する。

根拠: `hooks/notify-slack.sh`, `install.sh:33-45`, `install.sh:165-186`

### access / token log hooks

`log-access-prompt.sh`、`log-access-tool.sh`、`log-access-stop.sh` はユーザー指示、tool access、modified files を session file / pending file / monthly log に記録する。`log-token-usage.sh` は transcript usage を集計して token usage log に追記する。

根拠: `hooks/log-access-prompt.sh`, `hooks/log-access-tool.sh`, `hooks/log-access-stop.sh`, `hooks/log-token-usage.sh`

## Templates

`templates/issue.md` は issue draft、`templates/pr.md` は PR body、`templates/readme.md` は README scaffold の template である。commands は installed path として `~/.config/claude-code-kit/templates/*.md` を参照する。

根拠: `templates/issue.md:1-25`, `templates/pr.md:1-32`, `commands/task.md:131-138`

## Tests

`tests/hooks/test-approval-hooks.sh` は PreToolUse hook の shell verification である。破壊的 Bash block、session-approved があっても破壊的操作を block すること、read-only approval、session-approved approval、session temp 配下の Write/Edit approval、session temp 範囲外や symlink session temp の prompt fallback、cleanup hook による current session temp directory 削除、write-effect / ambiguous command の prompt fallback、`guard-destructive-cmd.sh` の JSON block output を検証する。また working repo dynamic defense として、Write / Edit / apply_patch / rm -rf の repo 内パス承認・WIP commit 作成・repo 外 prompt fallback・repo root / .git / 複数パス / 変数展開の除外・clean tree での WIP commit 非作成を検証する。

根拠: `tests/hooks/test-approval-hooks.sh:1-407`

`tests/commands/test-pr-review.sh` は `/pr-review` の declarative workflow contract を静的検証する。Claude/Codex の相互 routing、最大3ラウンド、HEAD SHA 結合、別 reviewer identity、session-approved 制限、GitHub review 投稿、および merge・main 同期・branch 削除の禁止を確認する。

根拠: `tests/commands/test-pr-review.sh:1-60`

`tests/commands/test-report-review.sh` は exact report label routing、read-only boundary、標準出力 sections、Git/GitHub write command の不在、command/skill catalog の整合性を静的検証する。

根拠: `tests/commands/test-report-review.sh:1-72`

## Install and Status Line

`install.sh` は `commands/*.md` を `~/.claude/commands/` と `~/.codex/commands/`、`hooks/*.sh` を `~/.claude/hooks/` と `~/.codex/hooks/`、`skills/*/` を `~/.codex/skills/`、`templates/*.md` を `~/.config/claude-code-kit/templates/` に symlink する。その後 `jq` があれば migration helper（`remove_claude_hook` / `remove_codex_hook`）で旧 hook entry を除去してから `add_claude_hook` / `add_codex_hook` で新 entry を追加する。idempotent な設計のため複数回実行しても重複しない。Codex hooks は `/hooks` で review/trust してから利用する前提で案内する。

`setup_statusline.sh` は `scripts/statusline.sh` を `~/.claude/statusline.sh` に symlink し、settings に `statusLine` を追加する。`scripts/statusline.sh` は stdin JSON から context / five-hour / seven-day rate limit を抽出して表示する。

根拠: `install.sh:12-188`, `setup_statusline.sh:6-55`, `scripts/statusline.sh:10-83`

## VitePress Site and CI

`site/package.json` は `docs:dev`, `docs:build`, `docs:preview` を定義する。dependencies は `@fortawesome/fontawesome-free`、devDependencies は `vitepress`。lock file では `@fortawesome/fontawesome-free` 6.7.2 と `vitepress` 1.6.4 が解決される。

`site/.vitepress/config.mts` は VitePress の `locales` オプションで多言語対応（i18n）を定義する。`root`（英語 / en-US）、`ja`（日本語 / ja-JP）、`zh`（中国語簡体字 / zh-CN）の 3 ロケールを持ち、各ロケールに nav・sidebar・footer を個別に定義する。コンテンツは `site/`（英語）、`site/ja/`（日本語）、`site/zh/`（中国語）に配置される。日本語版の concept・policy・specification ページは `docs/L0_concept/` および `docs/L3_implementation/specification_summary.md` を `@include` で参照する。

`.github/workflows/deploy.yml` は main push と `workflow_dispatch` を trigger とし、Node.js 24 で `site/` に対して `npm ci` と `npm run docs:build` を実行し、`site/.vitepress/dist` を GitHub Pages に deploy する。

根拠: `site/package.json:1-14`, `site/package-lock.json:765-766`, `site/package-lock.json:2486-2487`, `site/.vitepress/config.mts:1-183`, `.github/workflows/deploy.yml:1-53`

## 未確認事項

現時点で仕様サマリに混在させた未確認事項はない。
