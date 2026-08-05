# /init-docs specification

## 目的・役割

`commands/init-docs.md` は repository の実体を再観測し、L0-L3 docs、repo profile、README、AI guidance を再構築する重い初期化 workflow である。

根拠: `commands/init-docs.md:1-35`

## 動作の概要

専用 branch 上で repository/tooling を観測し、docs と README の整合性を検証した後、ユーザー承認を得て commit と PR を作成する。

根拠: `commands/init-docs.md:27-49`, `commands/init-docs.md:353-423`

## 主要な判定ロジック

README scaffold の基準は `${TEMPLATES_DIR}/readme.md` である。`TEMPLATES_DIR` は Claude Code では `~/.claude/templates`、Codex CLI では `~/.codex/templates` とする。

根拠: `commands/init-docs.md:3-5`, `commands/init-docs.md:275-292`

## 重要な設計判断

template 実体を repository に保持し、agent 固有 installed path の symlink から参照することで、同じ scaffold を Claude/Codex の双方で利用する。

- **L0（`docs/L0_concept/concept.md`・`policy.md`）は存在しない場合のみ新規作成し、既に存在する場合は再実行時も一切変更しない**（issue #273）。以前は「`/init-docs` 再実行時、または設計方針の根本的変更があった場合」に L0 も再生成する設計だったが、L0 はプロジェクトの最も核となる意思決定の記録であり 100% ユーザーが管理すべきという方針に基づき変更した。既存 L0 への追記が必要な場合は `/concept-maker` がユーザー承認を経て行う唯一の経路であり、`/init-docs` はこれを代替しない。Phase 4（整合性検証）の docs → 実体検証も、L0 が生成・更新対象でない場合はこれを対象に含めない。

根拠: `commands/init-docs.md:23`, `commands/init-docs.md:153-168`, `commands/init-docs.md:214`, issue #273

## 統合ポイント

- entry from `/docs-sync` HARD STOP or explicit user invocation
- README template: `${TEMPLATES_DIR}/readme.md`
- output: `docs/.ai/repo.profile.json`, L1-L3 docs（常時）、L0 docs（存在しない場合のみ）、README, CLAUDE.md/AGENTS.md
- L0 昇格の実行経路: `commands/concept-maker.md`（`/init-docs` はこの役割を代替しない）

## 注意事項・既知の制限

- 通常の局所 docs 更新には使用しない
- commit/PR 前にユーザー確認が必須
- 既存 L0 の内容を更新・修正したい場合でも、このコマンドでは行えない。`/concept-maker` を使うこと

## 変更履歴（git log より自動生成）

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
