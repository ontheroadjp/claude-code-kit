# CLAUDE.md specification

## 目的・役割

`CLAUDE.md`（リポジトリルート）は、このリポジトリ自身に対する project-local な AI 運用ドキュメントである。`AGENTS.md` はこのファイルへの symlink として、このリポジトリで作業する Codex CLI にも同じ内容を届ける。

配布用（`~/.claude/CLAUDE.md`・`~/.codex/AGENTS.md` の symlink 先）は `global/CLAUDE.md` に分離されている（issue #365）。分離直後の現時点では両ファイルは同一内容だが、今後 `global/CLAUDE.md` は `/work` を通じた汎用フレームワークの改善対象、このファイル（ルート `CLAUDE.md`）は他のどのリポジトリとも同じく `/init-docs` が観測・再生成する project-local な内容として、別々に発展していく想定である。

根拠: `CLAUDE.md:1-15`, `global/CLAUDE.md`, `docs/.ai/repo.profile.json`（`deploy.claude_md`, `deploy.codex_agents_md`）, issue #365

## 動作の概要

- command routing と repository 操作ルールを定義する
- symlink-only 原則と docs/task workflow の境界を示す
- local tooling と template installed path を記録する

根拠: `CLAUDE.md:13-109`

## 主要な判定ロジック・フロー

template の実体は repository の `templates/` に保持する。Claude Code は `~/.claude/templates/*.md`、Codex CLI は `~/.codex/templates/*.md` の symlink 経由で同じ実体を参照する。

根拠: `CLAUDE.md:44-51`

コマンド一覧に `work-multi.md` を持つ（issue #296）。`/work` と同一ワークフローを `EnterWorktree` 隔離下で実行する明示的 opt-in 入口で、AI が自動選択するデフォルトルーティングには含めない（通常作業は引き続き `/work` がデフォルト）。並行セッションのバッチが分かった時点で最初のセッションを含む全セッションに使うという運用ルール、および `node_modules` 等の依存ディレクトリが symlink 経由で複数セッション間に共有されるという既知の限界を明記する。

根拠: `CLAUDE.md:23`

「リポジトリへの操作ルール（必須）」節は、安全性が実行時変数に依存する危険操作（例: `rm -f "$VAR"`）について、read-only な解決ステップ → リテラル値埋め込みの2段階（resolve-then-embed）に分けることを AI に義務付ける。これは `hooks/auto-approve-readonly.sh` がコマンドテキストを実行せずに静的判定のみ行うという制約（推測・実行禁止）に対応するための運用側のルールであり、hook 側の `is_rm_f_on_safe_literal_path` によるリテラルパス自動承認と対になっている。

根拠: `CLAUDE.md:71-80`, `hooks/auto-approve-readonly.sh`（`is_rm_f_on_safe_literal_path`）, issue #248

「リポジトリへの操作ルール（必須）」節には「絞り込み読み（citation-based narrowed read）の検証」もある。`docs/L3_implementation/specification_summary.md` のような大きい集約 doc は見出し Grep で対象範囲を絞ってから `offset`/`limit` で対象読みし、L3 per-file doc の `根拠: <file>:<line-range>` citation を使った対象読みも含め、絞り込み読みした内容が期待する見出し・目印を実際に含んでいるかを確認してから信頼する。含んでいない場合（citation が古い行範囲を指す stale citation）は Glob/Grep での再検索または全文 Read へフォールバックし、citation の起点となった doc が古い可能性をユーザーに報告する。`commands/work.md` の investigation phase はこの原則への参照のみを持ち、手順を重複して記述しない。

根拠: `CLAUDE.md:82-94`, `commands/work.md:67-76`, issue #363

## 重要な設計判断

`~/.claude/` と `~/.codex/` を symlink-only とすることで、agent ごとの installed path を提供しながら repository を唯一の編集対象として維持する。

resolve-then-embed 規約は `commands/coding-general.md`（ソースコード編集時の言語非依存原則）ではなく `CLAUDE.md` の操作ルール節に置く。対象がソースコード編集ではなく、AI が発行する Bash コマンドそのものの構造化方法であり、セッション開始時に必ず読まれるこのファイルの方が適切なため（issue #248 での判断）。

絞り込み読みの検証原則も同じ理由で `CLAUDE.md` に置く（issue #363）。検討した代替案:
- `commands/work.md` へのインライン追加: `commands/docs-sync.md` の Phase 2 に既に同種の検証手順が個別実装されており、work.md にも書くと同じ原則が複数コマンドへ重複してしまう（#362 は docs-sync.md 側をこの共有原則への参照に簡略化する追跡issue）
- Claude Code の `~/.claude/rules/`（`paths:` frontmatter で対象ファイル読込時のみ条件付きロード）: work.md の肥大化は避けられるが、Codex CLI はこの機構を持たないためこの安全策を完全に失い、両エージェントを常に並記して同一挙動を維持するこのリポジトリの設計原則に反する。また `paths:` ロードが実際の Read 呼び出しより先に間に合うかも未検証だった
- 結論: `CLAUDE.md` は `AGENTS.md` symlink 経由で Codex CLI にも届き、複数コマンドから参照される共有プロトコルを置く既存の場所（resolve-then-embed と同じ位置付け）でもあるため、これを採用した

**配布用ファイルと project-local ファイルの分離（issue #365）**: このリポジトリは「AI 実行基盤そのものを配布する」という特殊性ゆえ、リポジトリルートの `CLAUDE.md` が長らく配布物（`~/.claude/CLAUDE.md` の symlink 元）を兼ねており、他のどのリポジトリとも異なり「global 層」と「project-local 層」が同一ファイルに収束していた。この収束は、`/init-docs` が他リポジトリに対して行うのと同じ「project-local な CLAUDE.md の観測・再生成」をこのリポジトリ自身に適用できない、という歪みを生んでいた。検討した代替案:
- symlink-only 原則等のフレームワーク固有事項を `docs/L0_concept/policy.md` に一本化し、`/work` の G-1 で毎回 gate read する: L0 は repo-local のため、他リポジトリで作業中に `~/.claude/CLAUDE.md` を直接編集してしまう懸念への対処にはならず、かつ「レポをまたいだ修正」自体がそもそも AI の判断範囲外（人間の運用ルールで縛るべき事項）と判断し、この懸念自体を前提から外した
- 結論: 配布用ファイルを `global/CLAUDE.md` として物理的に分離し、`~/.claude/CLAUDE.md` と `~/.codex/AGENTS.md`（Codex CLI が `~/.codex/AGENTS.md` から project root まで AGENTS.md を加算的に連結する仕様を確認済み）の双方から symlink する。これによりルート `CLAUDE.md` は他リポジトリと同じ project-local な位置付けを取り戻す

## 統合ポイント

- `AGENTS.md`（project-local） → `CLAUDE.md`（project-local） symlink
- `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`（共に配布先） → `global/CLAUDE.md` symlink（手動、`README.md` の Global AI Instructions 手順）
- installer: `install.sh`（CLAUDE.md/AGENTS.md の配布は対象外、手動 symlink のまま）
- template source: `templates/*.md`

## 注意事項・既知の制限

- home directory 配下の symlink target を直接編集しない
- repository 変更は `/work` workflow を経由する

## 変更履歴（git log より自動生成）

- bc4ae7b feat(#296): add /work-multi worktree-isolated entry point
- 04ddbb4 fix(claude): default to Japanese responses unless instructed otherwise
- 91067f8 docs: initialize project documentation (init-docs)
- e6845d7 feat(#273): introduce L0 promotion queue and /concept-maker; make L0 write-once by /init-docs
- f330e18 docs: initialize project documentation (init-docs)
- ade5abd feat(#248): add literal-path rm auto-approval and resolve-then-embed convention
- 5a4ecc6 chore(#205): remove /pr-review; /work and /task now end at PR creation
- 27f1861 feat(#76): install templates for claude and codex
- 5faaf5d docs: initialize project documentation (init-docs)
- 145876c fix(#185): align pr-review with repository workflow rules
