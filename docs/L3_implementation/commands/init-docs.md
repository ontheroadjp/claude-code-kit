# /init-docs specification

## 目的・役割

`commands/init-docs.md` は repository の実体を再観測し、L0-L3 docs、repo profile、README、AI guidance を再構築する重い初期化 workflow である。指示がない場合は standalone mode、明示された場合は documentation-only mode で動作する。

根拠: `commands/init-docs.md:1-35`

## 動作の概要

standalone mode では専用 branch 上で repository/tooling を観測し、docs と README の整合性を検証した後、ユーザー承認を得て commit と draft PR を作成する。documentation-only mode では現在ブランチを維持して Phase 1〜6 の再観測・再構築だけを実行し、commit・push・PR 作成を行わず呼び出し元へ返る。

根拠: `commands/init-docs.md:13-20`, `commands/init-docs.md:38-60`, `commands/init-docs.md:349-429`

## 主要な判定ロジック

実行モードは明示された指示だけで決まる。モード指定がなければ standalone mode とし、documentation-only mode が明示された場合だけ専用ブランチ作成と Phase 7 をスキップする。documentation-only mode は main ブランチ上では実行しない。

根拠: `commands/init-docs.md:13-20`, `commands/init-docs.md:43-60`, `commands/init-docs.md:365-370`

README scaffold の基準は `${TEMPLATES_DIR}/readme.md` である。`TEMPLATES_DIR` は Claude Code では `~/.claude/templates`、Codex CLI では `~/.codex/templates` とする。

根拠: `commands/init-docs.md:3-5`, `commands/init-docs.md:275-292`

## 重要な設計判断

template 実体を repository に保持し、agent 固有 installed path の symlink から参照することで、同じ scaffold を Claude/Codex の双方で利用する。

- **L0（`docs/L0_concept/concept.md`・`policy.md`）は存在しない場合のみ新規作成し、既に存在する場合は再実行時も一切変更しない**（issue #273）。以前は「`/init-docs` 再実行時、または設計方針の根本的変更があった場合」に L0 も再生成する設計だったが、L0 はプロジェクトの最も核となる意思決定の記録であり 100% ユーザーが管理すべきという方針に基づき変更した。既存 L0 への追記が必要な場合は `/concept-maker` がユーザー承認を経て行う唯一の経路であり、`/init-docs` はこれを代替しない。Phase 4（整合性検証）の docs → 実体検証も、L0 が生成・更新対象でない場合はこれを対象に含めない。

根拠: `commands/init-docs.md:23`, `commands/init-docs.md:153-168`, `commands/init-docs.md:214`, issue #273

standalone mode の Phase 7-3（commit）は、変更ファイルを個別に `git add` した後、直接 `git commit` はせず `/git-commit` を `fixed_message`（固定の init-docs commit message）で呼び出す（issue #300）。ステージングは従来どおり `/init-docs` 自身が担い、`/git-commit` はコミット実行のみを担う。これにより `docs/init-docs-<YYYYMMDD>` ブランチを再開した際に HEAD から連続する `wip:` commit があれば `/git-commit` Step 2 の WIP 正規化で自動的に squash されてからこの固定メッセージで commit される。`/git-commit` Step 1（ブランチが main なら切替）は Phase 7-2 で既に non-main ブランチであることを確認済みのため実質 no-op であり、既存の branch verification gate と衝突しない。Phase 7-4（`gh pr create --draft`）は変更していない。

根拠: `commands/init-docs.md:377-401`, issue #300

## 統合ポイント

- standalone invocation、または documentation-only mode を明示するドキュメントワークフローからの委譲
- README template: `${TEMPLATES_DIR}/readme.md`
- output: `docs/.ai/repo.profile.json`, L1-L3 docs（常時）、L0 docs（存在しない場合のみ）、README, CLAUDE.md/AGENTS.md
- L0 昇格の実行経路: `commands/concept-maker.md`（`/init-docs` はこの役割を代替しない）
- standalone mode の commit 実行: `commands/git-commit.md`（`fixed_message` 呼び出し。issue #300）

## 注意事項・既知の制限

- 通常の局所 docs 更新には使用しない
- standalone mode の commit/PR 前にユーザー確認が必須。documentation-only mode は commit/PR を行わない
- 既存 L0 の内容を更新・修正したい場合でも、このコマンドでは行えない。`/concept-maker` を使うこと

## 変更履歴（git log より自動生成）

- 65a9329 feat(#302): resume task after docs-sync hard stop
- e6845d7 feat(#273): introduce L0 promotion queue and /concept-maker; make L0 write-once by /init-docs
- 27f1861 feat(#76): install templates for claude and codex
- 2137bed Merge origin/main into docs/init-docs-branch-before-editing
- 019a6b6 docs(#140): start init-docs work on branch
- b6b91f1 feat(#138): update init-docs local tooling guidance
- ad364de docs(init-docs): add Phase 7 commit & PR creation workflow
- 3b990cf fix(#50): remove primary_docs from Phase 2 schema example to prevent premature writing
- 5497931 fix(#50): set primary_docs after Phase 3 generation, not as planned paths in Phase 2
- 3c7e474 fix(#50): primary_docs population must reference planned Phase 3 paths, not existing files
- 3e24c4a feat(#50): add primary_docs to repo.profile.json as lightweight SSOT for investigation
