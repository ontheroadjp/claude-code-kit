# CLAUDE.md

このファイルは AI 運用の起点となる情報をまとめる。Claude Code がこのリポジトリで作業する際はここを先に読む。
指示がない限り日本語で対応すること。

## このリポジトリについて

作業開始時に `README.md` の以下のセクションを読み、リポジトリ固有のコンテキストを把握すること:

- **Features**: アクティブな機能・コマンド一覧
- **Design Principles**: 守るべき設計制約
- **Usage**: run/test/build コマンド・開発手順

## Custom / Command の使い分け（AI向けルール）

**重要: PR レビューコメントへの対話対応は `/review-resolve`、それ以外の全作業は直ちに `/work` を呼ぶこと。`/work`（および委譲先の `/task`）のゴールは ready PR の作成までであり、PR 作成後の自動レビューは行わない。以降のレビュー・マージは人間、または `/review-resolve`・`/codex-review` を手動起動して行う。`report` label の issue は `/work #N` が `/report-review` へ委譲し、read-only 評価だけを行う。`hazard-candidate` label の issue は `/work #N` の前に `/triage-issues-for-hazard` で人間審査する。漠然としたアイデアから issue を作成したい場合のみ任意で `/new-issue` を先に使い、その後 `/work` で実装に入る。調査は `/work` 内で行う。`/docs-sync` が L0 昇格候補ありを案内した場合のみ任意で `/concept-maker` を使う。**

- **review-resolve.md**: PR レビューコメント対応専用のエントリポイント。`/work` を経由せず自己完結（checkout → 実装 → commit → push → 返信）。ユーザーが `/review-resolve #N` で直接呼び出す。
- **work.md**: review-resolve 以外の全作業のエントリポイント。ゲート確認・ワークスペース管理を行い、report issue は report-review.md、hazard-candidate issue は triage-issues-for-hazard.md、それ以外は現状調査後に task.md または patch.md へ委譲する。
  - `report` label の issue → report-review.md を Read し、実装・branch 作成を行わず評価して終了
  - docs 変更不要 → patch.md を Read して patch フロー（issue/PR なし、branch + commit → ユーザーが ff-merge）
  - docs 変更あり → task.md を Read して task フロー（issue 自動生成 → 実装 → ドラフト PR 作成 → /docs-sync へ引き継ぎ）
- **work-multi.md**: `/work` と全く同じワークフローを、`EnterWorktree` で作成した専用 worktree 内で実行する明示的 opt-in 入口（issue #296）。複数セッションが同じ working tree を共有すると `git checkout` が他セッションの作業中ファイルを書き換える衝突が起こり得るため、意図的に並行セッションを走らせるとわかっている場合に使う。**「2セッション目以降だけ隔離すればよい」という判断はしない** — どのセッションが「隔離不要な primary」かを常に追跡するのは同種の人為ミスの温床になるため、並行実行するバッチが分かった時点で、最初のセッションを含む全セッションで `/work-multi` を使う。通常の単一セッション作業では引き続き `/work` を使う（overhead なし）。untracked ファイル・ディレクトリ（`.git`・`.claude` を除く）は worktree 作成後に自動で symlink されるが、これには `node_modules` 等セッション中に書き換わる依存ディレクトリも含まれるため、同じ依存ディレクトリを持つ複数 `/work-multi` セッションでパッケージマネージャの書き込み操作（`npm install` 等）を同時実行しないこと。
- **report-review.md**: `report` label の issue を read-only で評価し、Facts / Assessment / Opinions / Proposals / Risks and Unknowns を標準出力へ提示する。ファイル・Git・GitHub を変更しない。
- **new-issue.md**: 漠然としたアイデアから 1 件または複数件の整形された issue を生成する任意の pre-`/work` エントリポイント。issue 作成のみで実装は行わない。
- **triage-issues.md**: open issue を現状 docs と照合し、stale / inconsistent / duplicated / unclear / ready に分類するスタンドアロン入口。issue 操作はユーザー承認後のみ行う。
- **codex-review.md**: Codex CLI で PR をレビューし、`CODEX_REVIEW_TOKEN` がある場合に approve/request-changes を投稿する。変更要求時は `/review-resolve` へ引き継ぐ。
- **task.md**: ドキュメント変更を伴う実装に特化。issue 自動生成〜実装〜ドラフト PR 作成まで。docs/* は変更しない。
- **patch.md**: ドキュメント変更を伴わない軽微な修正に特化。issue/PR 不要。branch + commit → ユーザーが main へマージ。スコープが広がった場合は /task へエスカレーション。
- **docs-sync.md**: git diff を事実として docs を最小更新し、ドラフト PR を公開する。HARD STOP 時は /init-docs を要求して終了する。L0（`docs/L0_concept/`）には書き込まず、L0 相当の記述を検知した場合は候補を `docs/.ai/l0_candidates.md` に積んで /concept-maker の実行を案内するに留める。
- **init-docs.md**: repo の実態把握と設計ドキュメント再構築。重い初期化。docs-sync が説明不能になった時点でここに戻る。L0（`docs/L0_concept/`）は存在しない場合のみ新規作成し、既に存在する場合は再実行時も一切変更しない。
- **concept-maker.md**: `docs/.ai/l0_candidates.md` に溜まった L0 昇格候補を、ユーザーとの壁打ちと明示的承認を経て L0 へ追記する唯一の経路。スタンドアロン入口で `/docs-sync` が候補ありを案内した時にユーザーが呼び出す。

## 重要な設計原則

- **symlink-only 原則**: `~/.claude/`・`~/.codex/` 配下には実体ファイルを置かず、全て本リポジトリへの symlink とする。このリポジトリが single source of truth。
- **L0（`docs/L0_concept/`）は 100% ユーザー管理**: AI が L0 に直接書き込むことはない。唯一の書き込み経路は `/concept-maker` によるユーザー承認付き追記であり、`/init-docs` は L0 が存在しない場合の初回作成のみを行う（既存 L0 は再実行時も変更しない）。
- ルーティング判定は単一質問: 「この変更で `docs/*` への追加・変更・削除が必要か？」
- 実装 issue は task フローで扱い、report issue は report-review フローで read-only 評価する（patch フローには issue 不要）
- task フローのコミット形式: `<type>(#<issue number>): <short description>` (Conventional Commits)
- ワークスペースのクリーン化は stash で行う（破壊的操作禁止）
- git diff が事実。AI の要約・解釈は補助情報にとどめる

## テンプレートの場所

- template の実体は本リポジトリの `templates/` に保持する
- Claude Code は `~/.claude/templates/*.md`、Codex CLI は `~/.codex/templates/*.md` の symlink 経由で参照する
- `templates/issue.md` → issue draft
- `templates/pr.md` → PR body
- `templates/readme.md` → 新規リポジトリの README.md 雛形

## リポジトリへの操作ルール（必須）

このリポジトリに影響する操作を行う際は、以下のルールに従うこと。

### ファイル編集・追加・削除の操作
**ファイルを編集・追加・削除する際は、`/review-resolve` フロー内を除き、必ず `/work` を実行すること。**
直接編集は禁止。`/work` 経由でルーティング判定・ブランチ作成・コミットを行う。
`/review-resolve` フロー内での実装は、PR ブランチ上で直接行い commit・push まで完結させる。

### npm 関連の操作
site は `site/` 配下で npm を使う。npm を利用する際は最初に `node --version` を実行して node をロードする。

### 一時ファイルの作成
AI agent がテスト・検証・中間生成物などで一時ファイルを作成する必要がある場合は、原則として `/tmp/claude-code-kit/$SESSION_ID/` 配下を使用すること。

- `/tmp` 直下や任意の一時ディレクトリには作成しない
- セッション終了時に Stop hook が `/tmp/claude-code-kit/$SESSION_ID/` を削除する
- 永続化が必要な成果物は一時ディレクトリではなく、作業計画で明示したリポジトリ内の対象パスに作成する

### 安全性が実行時変数に依存する危険操作（resolve-then-embed）
`rm` のような危険操作の対象パスが、その場で解決される shell 変数に依存する場合（例: `rm -f "$SESSION_APPROVED"`）、変数参照のまま実行してはならない。`hooks/auto-approve-readonly.sh` はコマンドテキストを静的にしか判定できず、変数の実際の値を実行せずに検証する手段がないため、これは常に確認プロンプトへ落ちる。

代わりに次の2段階に分けること:
1. **解決ステップ**: 値を得るためだけの read-only コマンド（例: `echo "$SESSION_APPROVED"`）を実行する。
2. **実行ステップ**: 手順1の出力に現れた値を、変数ではなく**リテラル文字列として**次のコマンドに埋め込む（例: `rm -f "<手順1で得た絶対パス>"`）。

hook はリテラル引数が既知の安全なパス（現在セッションの session-approved ファイル自身、または working repo 内）に一致する場合のみ自動承認する。対象がどちらにも一致しない場合や、変数・グロブ・複数引数が残っている場合は通常の確認フローに落ちる（安全側フォールバック）。

根拠・詳細: issue #248, `hooks/auto-approve-readonly.sh` の `is_rm_f_on_safe_literal_path`

### /work フロー対象外の操作（git 管理操作）
以下の操作は `/work` フローに乗らないが、実行前に必ず理由を説明しユーザーの明示的な確認を取ること:

- git 履歴の書き換え（`filter-repo` / `filter-branch` 等）
- `git push --force`
- ブランチの強制削除（`git branch -D`）
- その他、不可逆または共有状態に影響する git 操作

## このリポジトリへの変更作業

このリポジトリ自体を変更する場合も `/work` を呼ぶ。ただし:
- コマンド仕様・hooks・skills は Markdown + Bash が中心
- `site/` は VitePress + npm で、CI は `cd site && npm run docs:build` を実行する
- 変更後は `docs/` の更新が必要になることが多い（/docs-sync を呼ぶ）
- シンボリックリンクはリンク先の実体を変更するだけで反映される

## Local Tooling Environment

Observed by /init-docs on 2026-08-10:
- gh: 2.97.0
- gh auth: logged in to github.com; active account available for repository operations
- node: v24.16.0
- npm: 11.13.0
- Node runtime manager hints: mise (`node 24.16.0`)

Notes:
- If `gh` operations fail with API schema or compatibility errors, check `gh --version` first. Prefer upgrading `gh` when possible; if upgrading is impossible, use an equivalent `gh api` REST call or GitHub Web UI for the affected operation.
- Before npm operations, run `node --version` and `npm --version` to confirm Node.js and npm are available in the current shell. This also initializes Node.js in lazy-loaded runtime manager environments such as nvm or mise.
- Do not install or upgrade `gh`, Node.js, or npm automatically without explicit user confirmation.
