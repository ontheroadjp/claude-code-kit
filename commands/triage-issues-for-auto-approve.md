# /triage-issues-for-auto-approve

`/auto-approve-hazard-scan`（issue #284）が起票した `auto-approve-candidate` label 付き issue を一覧化し、issue ごとに AI ハザード分析を開示した上で、実装に進むかどうかをユーザーに確認するスタンドアロンのエントリポイントです。

- `/work`・`/task`・`/patch`・`/triage-issues`・`/auto-approve-hazard-scan` とは独立したワークフローです
- 判断基準が `/triage-issues`（issue 衛生全般のトリアージ）とは異なる（ハザード/リスクレビュー）ため、`commands/triage-issues.md` とは論理的にも構造的にも別ファイルとして維持し、`commands/triage-issues.md` 自体は変更しません
- **read-only です** — GitHub issue・label・PR・リポジトリファイルのいずれも変更しません。唯一の出力は標準出力です
- **`/work` を自身で起動しません** — 実装に進む場合は「`/work #N` をユーザー自身が実行してください」と案内するだけに留めます

---

## ワークフロー

### Step 0: 前提確認

- `gh auth status` でログイン済みであることを確認する
- ログインできていない場合は「gh にログインしてから再実行してください」と報告して終了する

### Step 1: 候補 issue 一覧取得

```bash
gh issue list --label auto-approve-candidate --state open --json number,title,body,url,createdAt --limit 200
```

取得件数をユーザーに報告する。0 件の場合は「`auto-approve-candidate` label の open issue はありません」と報告して終了する。

### Step 2: issue ごとの開示・承認

取得した issue を 1 件ずつ、以下の手順で処理する。

#### 2.1 ハザード分析の開示

issue 本文を `## Overview` / `## Evidence` / `## --explain Output` / `## Hazard Checklist` / `## Proposed Change (not implemented here)` / `## Done Criteria` のセクション見出しで分割し、以下の形式でそのまま提示する（要約・言い換えをしない — issue 本文の記述を根拠とする）:

```
---
Issue #XX: <title>
URL: <url>
作成日: <createdAt>

## Overview
<issue本文からそのまま転記>

## Evidence
<issue本文からそのまま転記>

## --explain Output
<issue本文からそのまま転記>

## Hazard Checklist
<issue本文からそのまま転記>

## Proposed Change (not implemented here)
<issue本文からそのまま転記>
```

上記のセクション見出しが本文中に見つからない場合（`auto-approve-hazard-scan.md` 以外の経路で作成された issue など）は、パースを行わず issue 本文全体をそのまま提示する。

#### 2.2 承認確認

**ユーザーに確認する:**
「この提案の実装に進みますか？（yes / no）」

- `yes` → 「`/work #<N>` を実行してください」と案内し、当該 issue 番号を「実装案内済み」リストに記録して次の issue へ進む
- `no` → 対応せず「見送り」リストに記録して次の issue へ進む

このステップでは `gh issue` の編集・コメント・label 操作は一切行わない。

### Step 3: 完了報告

全 issue を処理した後、以下を報告する:

```
## Triage-Issues-For-Auto-Approve Complete

候補総数: N 件
- 実装案内をした: N 件（issue 番号一覧）
- 見送り: N 件（issue 番号一覧）

実装に進む場合は、案内された issue 番号ごとにユーザー自身が `/work #N` を実行してください。
```

---

## スコープ外

- `gh issue` の編集・close・comment・label 操作（一切行わない）
- `/work` の自動起動（ユーザーが個別に `/work #N` を実行する）
- `hooks/auto-approve-readonly.sh` を含む既存コードの変更
- `auto-approve-candidate` issue の新規起票（`/auto-approve-hazard-scan` が担う）
- `commands/triage-issues.md` の変更・統合
