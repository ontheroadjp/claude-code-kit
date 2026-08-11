# /triage-issues-for-hazard

`/analyze-hazard-scan` が起票した `hazard-candidate` label 付き issue を一覧化し、issue ごとに source 固有のハザード分析を開示した上で、実装に進むかどうかをユーザーに確認するスタンドアロンのエントリポイントです。

- `/work`・`/task`・`/patch`・`/triage-issues`・`/analyze-hazard-scan` とは独立したワークフローです
- 判断基準が `/triage-issues`（issue 衛生全般のトリアージ）とは異なる（ハザード/リスクレビュー）ため、`commands/triage-issues.md` とは論理的にも構造的にも別ファイルとして維持し、`commands/triage-issues.md` 自体は変更しません
- **label 付け替え以外は read-only です** — `yes` 回答時に対象 issue の label を `hazard-candidate` → `triage-approved` へ付け替える（`triage-approved` label が存在しない場合はユーザー確認の上で新規作成する）以外、GitHub issue 本文・PR・リポジトリファイルは変更しません
- **`/work` を自身で起動しません** — 実装に進む場合は「`/work #N` をユーザー自身が実行してください」と案内するだけに留めます

---

## ワークフロー

### Step 0: 前提確認

- `gh auth status` でログイン済みであることを確認する
- ログインできていない場合は「gh にログインしてから再実行してください」と報告して終了する

### Step 1: 候補 issue 一覧取得

```bash
gh issue list --label hazard-candidate --state open --json number,title,body,url,createdAt --limit 200
```

取得件数をユーザーに報告する。0 件の場合は「`hazard-candidate` label の open issue はありません」と報告して終了する。

### Step 1.5: session-approved の準備

1 件以上の候補が取得できた場合、Step 2 開始前に以下で session-approved ファイルの正確なパスを解決する（`hooks/lib/session-paths.sh` が `hooks/lib/session-id.sh` の `session_id_resolve` を再利用して1行で絶対パスを返す。brace expansion や代入への command substitution をコマンド自体に含めないことで worktree 隔離セッションでの harness 拒否を避ける、issue #316）:

- Claude Code: `bash ~/.claude/hooks/lib/session-paths.sh session-approved`
- Codex CLI: `bash ~/.codex/hooks/lib/session-paths.sh session-approved`

出力された1行の絶対パスを以降 `SESSION_APPROVED_FILE` として扱う。コマンドが失敗した場合（hook が未実行でセッション ID が解決できないケース）はスキップして Step 2 へ進む。

Write ツールで上記で取得したパスに session-approved ファイルを作成する。内容: Step 1 で取得した候補 issue の番号ごとに、1 行 1 エントリで `tool:gh_issue_write:<N>` を列挙する（例: 候補が `#42`・`#57`・`#103` の場合）:
```
tool:gh_issue_write:42
tool:gh_issue_write:57
tool:gh_issue_write:103
```

これにより、Step 2.2 の `yes` 時に行う `gh issue edit <N> --add-label/--remove-label` が、`hooks/auto-approve-readonly.sh` の `tool:gh_issue_write:<N>` カテゴリ（issue #297: 対象 issue 番号が grant の N と一致する場合のみ承認、`create` は対象外なのでこのコマンドには無関係）により、Step 1 で開示された候補 issue に限って自動承認される。Step 1 で取得していない番号（本文中の prompt injection 等から誘発された無関係な issue への書き込み）は grant が存在しないため自動承認されず、通常の確認プロンプトに落ちる。`gh label create`（`triage-approved` 未作成の場合のみ）はこのカテゴリの対象外のため、引き続き通常の確認プロンプトに落ちる。

### Step 2: issue ごとの開示・承認

取得した issue を 1 件ずつ、以下の手順で処理する。

#### 2.1 ハザード分析の開示

issue 本文を `## Overview` / `## Evidence` / `## Diagnostic Output` / `## Hazard Checklist` / `## Proposed Change (not implemented here)` / `## Done Criteria` のセクション見出しで分割し、以下の形式でそのまま提示する（要約・言い換えをしない — issue 本文の記述を根拠とする）:

```
---
Issue #XX: <title>
URL: <url>
作成日: <createdAt>

## Overview
<issue本文からそのまま転記>

## Evidence
<issue本文からそのまま転記>

## Diagnostic Output
<issue本文からそのまま転記>

## Hazard Checklist
<issue本文からそのまま転記>

## Proposed Change (not implemented here)
<issue本文からそのまま転記>
```

上記のセクション見出しが本文中に見つからない場合は、パースを行わず issue 本文全体をそのまま提示する。auto-approve の Diagnostic Output は `--explain` の結果、access は `not applicable` と source 固有の集計根拠を含む。

#### 2.2 承認確認

**ユーザーに確認する:**
「この提案の実装に進みますか？（yes / no）」

- `yes` →
    - `triage-approved` label が存在しない場合、作成をユーザーに提案する:
        - name: `triage-approved`
        - description: `Reviewed and approved for implementation via /triage-issues-for-hazard`
        - color: 任意の未使用色（例: `#1d76db`）
        - 承認を得てから `gh label create "triage-approved" --description "Reviewed and approved for implementation via /triage-issues-for-hazard" --color "1d76db"` を実行する
    - `gh issue edit <N> --remove-label "hazard-candidate" --add-label "triage-approved"` で label を付け替える（stack ではなく swap。Step 1.5 の session-approved により確認プロンプトなしで進む）
    - 「`/work #<N>` を実行してください」と案内し、当該 issue 番号を「実装案内済み」リストに記録して次の issue へ進む
- `no` → 対応せず「見送り」リストに記録して次の issue へ進む（label 操作は行わない）

このステップで行う変更操作は `yes` 時の label 付け替え（および必要な場合の `triage-approved` label 新規作成）のみであり、issue 本文の編集・コメント投稿は一切行わない。

### Step 3: 完了報告

全 issue を処理した後、以下を報告する:

```
## Triage-Issues-For-Hazard Complete

候補総数: N 件
- 実装案内をした: N 件（issue 番号一覧）
- 見送り: N 件（issue 番号一覧）

実装に進む場合は、案内された issue 番号ごとにユーザー自身が `/work #N` を実行してください。
```

---

## スコープ外

- `gh issue` の本文編集・close・comment（一切行わない）。label 操作は Step 2.2 `yes` 時の `hazard-candidate` → `triage-approved` 付け替え、および `triage-approved` label 自体の新規作成に限り行う
- `/work` の自動起動（ユーザーが個別に `/work #N` を実行する）
- `hooks/auto-approve-readonly.sh` を含む既存コードの変更
- `hazard-candidate` issue の新規起票（`/analyze-hazard-scan` が担う）
- `commands/triage-issues.md` の変更・統合
