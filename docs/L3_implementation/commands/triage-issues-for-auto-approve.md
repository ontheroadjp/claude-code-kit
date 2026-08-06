# `commands/triage-issues-for-auto-approve.md` specification

## 目的・役割

`/auto-approve-hazard-scan`（issue #284）が起票した `auto-approve-candidate` label 付き open issue を一覧化し、issue ごとに AI ハザード分析を開示した上で実装に進むかどうかをユーザーに確認する read-only のスタンドアロンワークフロー。issue #282（アンブレラ）配下の issue #285 として追加された。`/work`・`/task`・`/patch`・`/triage-issues`・`/auto-approve-hazard-scan` とは独立している。

根拠: `commands/triage-issues-for-auto-approve.md:1-9`

## 動作の概要

3 Step で構成される:

```
Step 0: gh auth status 確認
Step 1: gh issue list --label auto-approve-candidate --state open で候補一覧を取得
Step 2: issue ごとに本文をセクション見出しで分割して開示し、
        「実装に進みますか？（yes/no）」を確認。yes の場合は
        「/work #<N> を実行してください」と案内するのみ（/work は呼ばない）
Step 3: 実装案内をした件数・見送り件数を報告
```

根拠: `commands/triage-issues-for-auto-approve.md:14-72`

## 主要な判定ロジック・フロー

- 候補データは `gh issue list --label auto-approve-candidate --state open` から取得する。closed issue は対象外
- issue 本文は `## Overview` / `## Evidence` / `## --explain Output` / `## Hazard Checklist` / `## Proposed Change (not implemented here)` / `## Done Criteria` の固定セクション見出しで分割し、要約・言い換えをせずそのまま転記して提示する（`auto-approve-hazard-scan.md` の issue 起票テンプレートに合わせた設計）
- 見出しが見つからない issue（想定外の経路で作成された場合）は本文全体をそのまま提示するフォールバックを持つ
- 承認は issue 単位（`yes`/`no`）で、`/auto-approve-hazard-scan` のような一括バッチ承認ではない — issue ごとに個別のハザード内容を吟味した上で判断すべきという性質のため
- yes の場合も `/work` を自身で起動せず、案内のみに留める。issue #285 の Scope に明記された「`/work` を呼ばない」という制約をそのまま踏襲した

根拠: `commands/triage-issues-for-auto-approve.md:24-56`

## 重要な設計判断とその理由

`commands/triage-issues.md` とは別ファイルとして維持している。判断基準が異なる（`/triage-issues` は issue 衛生全般 — stale/inconsistent/duplicated/unclear/ready の分類、こちらはハザード/リスクレビュー）ため、1つのコマンドに統合すると判断基準が混在し、`auto-approve-candidate` issue 特有のセクション構造（Evidence・`--explain` Output・Hazard Checklist）を汎用トリアージのロジックに埋め込むことになり複雑化するため、issue #285 の合意通り分離を維持した。

`/work` を自身で起動しない設計とした理由は、ハザード分析はあくまで AI 提案であり、実装着手の最終判断とその起動自体を人間の明示的な操作に委ねるため（`/auto-approve-hazard-scan` が issue 作成をバッチ承認制にしているのと同じ「人間ゲート」の思想を、実装着手の起動タイミングにも適用した）。

根拠: issue #285, `commands/triage-issues-for-auto-approve.md:9-12`

## 統合ポイント

- 呼び出し元: なし（スタンドアロン entry point。ユーザーが直接起動する）
- 参照するもの: `/auto-approve-hazard-scan` が起票した `auto-approve-candidate` label 付き issue（`gh issue list`）
- Codex wrapper: `skills/triage-issues-for-auto-approve/SKILL.md`
- 後続ワークフロー: yes と回答された issue は、ユーザーが個別に `/work #N` を起動して初めて実装される

## 注意事項・既知の制限

- read-only。`gh issue` の編集・close・comment・label 操作、`/work` の自動起動、`hooks/auto-approve-readonly.sh` を含む既存コードの変更のいずれも行わない
- セクション分割は見出し文字列の一致に依存するため、`auto-approve-hazard-scan.md` のテンプレート以外の形式で作成された `auto-approve-candidate` issue は本文全体表示にフォールバックする（パース精度は issue 本文の構造に依存する）
- `triage-issues.md`・`auto-approve-hazard-scan.md` 同様、専用の自動テスト（shell テストスイート）は存在しない

## 変更履歴（git log より自動生成）

- 7aa4615 feat(#285): add /triage-issues-for-auto-approve command
