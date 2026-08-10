# `templates/pr.md`

## 目的・役割

`/task` Phase 2 Step 1 が使う PR 本文テンプレート。issue との紐付け、変更内容の要約、`/docs-sync` への引き継ぎ事項（handoff）の各セクションで構成される。

根拠: `templates/pr.md:1-33`

## 動作の概要

- `Closes #[issue number]` で issue と自動リンクする
- `### Changed Files` / `### Change Type` で変更内容を要約する
- `### Handoff Notes for /docs-sync` で、git diff から読み取れない設計意図・副作用・注意箇所を `/docs-sync` へ引き継ぐ
- `### Notes for Reviewers` で人間レビュアー向けの補足を記載する

根拠: `templates/pr.md:1-33`

## 重要な設計判断

### `Specific docs sections to update` フィールドが citation 形式を優先する理由（issue #307）

`/work`・`/task` Phase 1 の投資調査で `docs/L3_implementation/specification_summary.md` の該当セクションを既に特定しているにもかかわらず、`/docs-sync` Phase 2 が毎回独自に同じ箇所を再探索していたため、specification_summary.md が月次アクセスレポートで重複読み込みの上位ファイルになっていた（23回/月）。このフィールドを、既に解決済みの `docs/L3_implementation/specification_summary.md:<line-range>` citation を運ぶ handoff チャネルとして使うことで、`/docs-sync` Phase 1 Step 2 がその citation を抽出し、Phase 2 で `offset`/`limit` の対象読みとして再利用できるようにした。投資調査でセクションを特定できていない場合はファイル名・説明文で代替する（フォールバック）。

### Handoff Notes セクションが「git diff から読み取れない情報」に限定される理由

ファイル変更・API差分・設定値は git diff で機械的に判断可能なため、`/docs-sync` が独自に読み取れる。このセクションは、git diff からは読み取れない設計意図・副作用・誤読リスクに限定することで、`pr-body.md` の記述と git diff の実態が矛盾した場合に git diff を優先するという `/docs-sync` の方針（`docs/L3_implementation/commands/docs-sync.md`）と整合させている。

根拠: `templates/pr.md:23-29`, issue #307

## 統合ポイント

- 使用元: `commands/task.md` Phase 2 Step 1（`${TEMPLATES_DIR}/pr.md` を Read してテンプレートを埋め、`pr-body.md` として session temp に書き出す）
- 読み手: `commands/docs-sync.md` Phase 1 Step 2（`pr-body.md` を補助情報として解析）、`commands/git-pr.md`（PR body としてそのまま使用）
- template root: Claude Code は `~/.claude/templates`、Codex CLI は `~/.codex/templates`（`templates/README.md` 参照）

## 注意事項・既知の制限

- `Specific docs sections to update` の citation はあくまで「見つかっていれば書く」もので、投資調査でセクションを特定していない場合は従来通りファイル名・説明文で代替される。citation がない場合、`/docs-sync` は独自探索にフォールバックし挙動は変わらない
- citation の行範囲はその後の編集でズレる可能性があるが、`/docs-sync` 側は「見つからなければ独自探索」で吸収する設計になっている

## 変更履歴（git log より自動生成）

- 5e9bc3f feat(#307): carry specification_summary.md citations from /task to /docs-sync
- f0d7bc1 feat(#41): move templates/ to repo root, add partials/ symlink, clean up stale symlinks
- 0fac3e7 [/task:wip] #7 コマンドファイルと templates/ を commands/ に集約
- a29fa9f patch: PR テンプレートに Closes #[issue番号] を追加
- 275200d init-docs: reorganize repo with 4-command structure and updated docs
