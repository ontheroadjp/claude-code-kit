# `commands/concept-maker.md`

## 目的・役割

`docs/.ai/l0_candidates.md` に溜まった L0（`docs/L0_concept/concept.md`・`policy.md`）昇格候補を、ユーザーとの壁打ちと明示的承認を経て L0 へ追記する専用のスタンドアロン入口である。L0 への AI 書き込みは、`/init-docs` の初回新規作成を除けばこのコマンドのみが担う。

根拠: `commands/concept-maker.md:1-9`, issue #273

## 動作概要

Step 0 で前提（main ブランチ・クリーンな workspace・キュー非空）を確認し、Step 1 で候補を一覧提示し、Step 2 で候補ごとにソース文脈の把握 → 追記先ファイルの提示 → ドラフト提示 → ユーザーフィードバックによる再提示のループ → 明示的承認、を繰り返す。Step 3 で `concept/<YYYYMMDD>` ブランチ上に承認済み候補を追記・commit し、Step 4 でユーザーへ ff-merge 手順を案内する。issue・PR は作らない。

根拠: `commands/concept-maker.md:15-76`

## 重要な設計判断

### 機械的な一括生成をしない理由

L0 はプロジェクトの最も核となる意思決定の記録であり、将来的に自然言語のラフな指示から AI が自律的に実装を進める際の指針になる想定である。曖昧・不正確な文言が紛れ込むとその後の AI 判断がユーザーの意図から外れる原因になるため、候補ごとに個別の壁打ち（ドラフト → 修正 → 再提示の反復）を必須とし、要約や機械的な言い換えで済ませない。

### issue・PR を作らない理由

L0 への変更は他のどの docs 更新よりもユーザー自身の判断が主体であるべきであり、Step 2 の壁打ちと明示的承認そのものが実質的なレビュープロセスを兼ねる。`commands/patch.md` と同じ「軽量な branch + commit + ユーザー手動 ff-merge」の完結パターンを採用し、承認の主体が最後までユーザー自身であることを保つ。

### L0 書き込み経路を `/init-docs` と `/concept-maker` の2つに限定する理由

`/docs-sync` は L0 相当の記述を検知しても `docs/.ai/l0_candidates.md` へキューイングするのみで L0 自体には書き込まない（`commands/docs-sync.md` Phase 3 Step 2b）。`/init-docs` は L0 が存在しない場合の初回新規作成のみを行い、既存 L0 は再実行時も変更しない（`commands/init-docs.md`）。この結果、既存 L0 への追記は `/concept-maker` の壁打ち・承認フローを経由する以外に経路がなくなる。

根拠: `commands/concept-maker.md:80-86`, `commands/docs-sync.md:167-176`, `commands/init-docs.md:153-168`, issue #273

## 統合ポイント

- 起点: `/docs-sync` Phase 4 がキュー非空を案内した際にユーザーが手動で呼び出す（自動連鎖しない）
- 入力: `docs/.ai/l0_candidates.md`（`/docs-sync` が Step 2b で追記）
- 出力: `docs/L0_concept/concept.md`・`policy.md` への追記、`docs/.ai/l0_candidates.md` の処理済み候補削除
- 呼び出すもの: `/git-commit`（`issue_number=none`, `allowed_types=[docs]`）

## 注意事項・既知の制限

- `/work`・`/task`・`/patch`・`/docs-sync`・`/init-docs` のいずれからも呼び出されない完全な standalone コマンドである
- キューが空、または全候補が見送りになった場合は Step 3（branch/commit）をスキップする
- merge 前に `docs/L0_concept/` の最終差分確認をユーザーに促す（`/patch` にはないこのコマンド固有の注意喚起）

## 変更履歴（git log より自動生成）

（次回 `/docs-sync` 実行時に自動追加される）
