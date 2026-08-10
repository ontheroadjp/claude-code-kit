# `commands/triage-issues-for-auto-approve.md` specification

## 目的・役割

`/auto-approve-hazard-scan`（issue #284）が起票した `auto-approve-candidate` label 付き open issue を一覧化し、issue ごとに AI ハザード分析を開示した上で実装に進むかどうかをユーザーに確認するスタンドアロンワークフロー。issue #282（アンブレラ）配下の issue #285 として追加された。`/work`・`/task`・`/patch`・`/triage-issues`・`/auto-approve-hazard-scan` とは独立している。`yes` 回答時の label 付け替え（issue #298）を除き read-only。

根拠: `commands/triage-issues-for-auto-approve.md:1-9`

## 動作の概要

4 Step で構成される:

```
Step 0: gh auth status 確認
Step 1: gh issue list --label auto-approve-candidate --state open で候補一覧を取得
Step 1.5: 候補が1件以上あれば session-approved ファイルを候補 issue 番号ごとの tool:gh_issue_write:<N> で作成（issue #297）
Step 2: issue ごとに本文をセクション見出しで分割して開示し、
        「実装に進みますか？（yes/no）」を確認。yes の場合は
        auto-approve-candidate → triage-approved へ label を swap してから
        「/work #<N> を実行してください」と案内する（/work は呼ばない）
Step 3: 実装案内をした件数・見送り件数を報告
```

根拠: `commands/triage-issues-for-auto-approve.md:14-96`

## 主要な判定ロジック・フロー

- 候補データは `gh issue list --label auto-approve-candidate --state open` から取得する。closed issue は対象外
- issue 本文は `## Overview` / `## Evidence` / `## --explain Output` / `## Hazard Checklist` / `## Proposed Change (not implemented here)` / `## Done Criteria` の固定セクション見出しで分割し、要約・言い換えをせずそのまま転記して提示する（`auto-approve-hazard-scan.md` の issue 起票テンプレートに合わせた設計）
- 見出しが見つからない issue（想定外の経路で作成された場合）は本文全体をそのまま提示するフォールバックを持つ
- 承認は issue 単位（`yes`/`no`）で、`/auto-approve-hazard-scan` のような一括バッチ承認ではない — issue ごとに個別のハザード内容を吟味した上で判断すべきという性質のため
- `yes` の場合、`auto-approve-candidate` label を外し `triage-approved` label を付け替える（stack ではなく swap）。`triage-approved` label が存在しない場合はユーザー確認の上で `gh label create` する。label 付け替え以降は `/work #N` が `commands/work.md` の auto-approve-candidate ゲートに再度ひっかからず通常の `/task` ルーティングに進める（issue #298）
- yes の場合も `/work` を自身で起動せず、案内のみに留める。issue #285 の Scope に明記された「`/work` を呼ばない」という制約をそのまま踏襲した

根拠: `commands/triage-issues-for-auto-approve.md:24-96`, issue #298

## 重要な設計判断とその理由

`commands/triage-issues.md` とは別ファイルとして維持している。判断基準が異なる（`/triage-issues` は issue 衛生全般 — stale/inconsistent/duplicated/unclear/ready の分類、こちらはハザード/リスクレビュー）ため、1つのコマンドに統合すると判断基準が混在し、`auto-approve-candidate` issue 特有のセクション構造（Evidence・`--explain` Output・Hazard Checklist）を汎用トリアージのロジックに埋め込むことになり複雑化するため、issue #285 の合意通り分離を維持した。

`/work` を自身で起動しない設計とした理由は、ハザード分析はあくまで AI 提案であり、実装着手の最終判断とその起動自体を人間の明示的な操作に委ねるため（`/auto-approve-hazard-scan` が issue 作成をバッチ承認制にしているのと同じ「人間ゲート」の思想を、実装着手の起動タイミングにも適用した）。

`auto-approve-candidate` → `triage-approved` の label 付け替えを stack（両 label 併存）ではなく swap にしたのは、`commands/work.md` 側のゲート判定を「`auto-approve-candidate` label の有無」という単純な条件のまま保つため。stack にすると `/work` 側が「`auto-approve-candidate` AND NOT `triage-approved`」という AND-NOT 条件を持つ必要が生じ、既存の report label チェック（単一 label の有無）と非対称になる（issue #298）。

session-approved に候補 issue 番号ごとの `tool:gh_issue_write:<N>` を書き込んで Step 2.2 の `gh issue edit <N> --add-label/--remove-label` を自動承認する設計は、issue #297 で `hooks/auto-approve-readonly.sh` の `check_session_approved()` が対象番号スコープに対応したことに伴う変更である。Step 1 で取得済みの候補一覧（`gh issue list --json number,...`）から番号を全て把握できるため、Step 1.5 の書き込み時点で全 grant 行を確定でき、issue 作成タイミングを待つような順序変更は不要だった（`commands/task.md` の Step 2 とは異なる点 — 詳細は `docs/L3_implementation/commands/task.md` 参照）。`gh label create`（`triage-approved` 未作成の場合のみ）はこのカテゴリの対象外のため、引き続き通常の確認プロンプトに落ちる。

番号スコープ化以前（issue #297 より前）は session 全体に対する単一の広い `tool:gh_issue_write` 許可だった。本コマンドは issue 本文（`/auto-approve-hazard-scan` が生成、場合によっては第三者が作成）を AI のコンテキストに読み込む性質上、prompt injection 経由で無関係な issue への書き込みを誘発される理論的リスクがあったが、Step 1 で開示した候補番号にのみ grant を限定したことでこのリスクは解消された（Step 1 で取得していない番号への `gh issue edit` 等は grant が存在せず自動承認されない）。

根拠: issue #285, issue #297, issue #298, `commands/triage-issues-for-auto-approve.md:9-12`, `commands/triage-issues-for-auto-approve.md:27-49`, `hooks/auto-approve-readonly.sh:1094-1141`

## 統合ポイント

- 呼び出し元: なし（スタンドアロン entry point。ユーザーが直接起動する）
- 参照するもの: `/auto-approve-hazard-scan` が起票した `auto-approve-candidate` label 付き issue（`gh issue list`）
- 書き込み先: 対象 issue の label（`yes` 時の `auto-approve-candidate` → `triage-approved` swap）、`triage-approved` label 自体（未存在時のみ新規作成）
- 連携先: `commands/work.md` の auto-approve-candidate ゲート（`triage-approved` への付け替えでゲートを解除する）
- Codex wrapper: `skills/triage-issues-for-auto-approve/SKILL.md`
- 後続ワークフロー: yes と回答された issue は、ユーザーが個別に `/work #N` を起動して初めて実装される

## 注意事項・既知の制限

- `yes` 時の label 付け替え（および `triage-approved` label 新規作成）を除き read-only。`gh issue` の本文編集・close・comment、`/work` の自動起動、`hooks/auto-approve-readonly.sh` を含む既存コードの変更のいずれも行わない
- セクション分割は見出し文字列の一致に依存するため、`auto-approve-hazard-scan.md` のテンプレート以外の形式で作成された `auto-approve-candidate` issue は本文全体表示にフォールバックする（パース精度は issue 本文の構造に依存する）
- `triage-issues.md`・`auto-approve-hazard-scan.md` 同様、専用の自動テスト（shell テストスイート）は存在しない
- `tool:gh_issue_write:<N>` は Step 1 で開示した候補 issue 番号ごとにスコープされる（issue #297）。Step 1 未取得の番号への `gh issue edit`/`comment`/`close`/`reopen`/`delete` は grant が存在せず自動承認されない

## 変更履歴（git log より自動生成）

- 4450e96 feat(#298): gate /work on auto-approve-candidate label, swap to triage-approved on approval
- 7aa4615 feat(#285): add /triage-issues-for-auto-approve command
