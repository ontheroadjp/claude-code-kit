# /auto-approve-hazard-scan

`logs/auto-approve/*.log` で `user_prompt` に落ちている定型処理コマンドから allowlist 拡張の候補を洗い出し、`hooks/auto-approve-readonly.sh --explain` の判定根拠をもとに AI が構造化ハザードチェックリストを作成し、既知ハザードが見つからない候補についてのみ `auto-approve-candidate` label 付き GitHub issue を起票する、issue #284 のパイプラインです。

- `/work`・`/task`・`/patch`・`/new-issue`・`/triage-issues` とは独立したスタンドアロンのワークフローです
- **hook（`hooks/auto-approve-readonly.sh`）や他の既存コードの変更は一切行いません** — このパイプライン唯一の書き込みは `gh issue create`（および初回のみ `gh label create`）です
- **AI による issue 起票はユーザーの明示的な一括承認なしに実行しません**（`/new-issue`・`/triage-issues` と同じ方針）
- 生成される issue はあくまで「提案」であり、実装するかどうかの判断と `/work` の起動は人間が行います

---

## ワークフロー

### Step 0: 前提確認

- 現在ブランチが `main` であることを確認する（実装は伴わないため、ブランチ切り替え・ゲートは不要）
- `gh auth status` でログイン済みであることを確認する。ログインできていない場合は「gh にログインしてから再実行してください」と報告して終了する

### Step 1: 集計スクリプトの実行

```bash
python3 scripts/analyze_auto_approve.py --all
```

標準出力の JSON から `routine_ops.patterns_needing_approval` を候補抽出の根拠として保持する（`--all` で全期間のログを対象にし、候補の見落としを防ぐ）。コマンドがゼロ以外で終了した場合はエラーをそのまま報告して終了する。

### Step 2: 候補コマンドの抽出

`patterns_needing_approval` の各パターンについて、`sample_commands`（頻度降順）の上位 3 件を候補コマンドとして抽出する。件数が 3 件未満のパターンは全件を候補にする。この時点でのコマンド文字列は生ログ由来の literal な文字列として扱い、推測で正規化・書き換えしない。

### Step 3: 重複チェック

```bash
gh label list --json name --jq '.[].name'
```

- `auto-approve-candidate` label が存在しない場合（初回実行）: 重複チェック対象なしとして Step 4 へ進む
- 存在する場合:
    ```bash
    gh issue list --label auto-approve-candidate --state all --json number,title,body,url --limit 200
    ```
    各候補コマンドについて、既存 issue の本文に同一のコマンド文字列（完全一致）が含まれていないか確認する。含まれていれば「既に提案済み」として当該候補を候補リストから除外する

### Step 4: `--explain` 診断の取得

`--explain` は実行中セッション自身の `session-approved` ファイルを fast path として参照するため（`hooks/auto-approve-readonly.sh:1776`）、分析者自身のセッションで既に `tool:git_write` 等が承認済みだと、本来 `user_prompt` になるべき候補も `approve` と誤診断される。**候補コマンドが「新規セッションでどう判定されるか」を診断するには、存在しないパスを指す `CLAUDE_CODE_KIT_SESSION_APPROVED_FILE` を指定して実行する**:

```bash
CLAUDE_CODE_KIT_SESSION_APPROVED_FILE=/nonexistent/session-approved \
  bash hooks/auto-approve-readonly.sh --explain "<候補コマンド>"
```

重複除外後の各候補コマンドについてこれを実行し、出力（セグメント分割・マッチした allow-shape・session-approved 状態・verdict）をそのハザードチェックリストの根拠として保持する。

### Step 5: ハザードチェックリストの作成

各候補コマンドについて、`hooks/auto-approve-readonly.sh` の該当関数（`is_safe_git_read_command` / `is_safe_local_git_write_command` / `is_safe_gh_command` 等、対象コマンドファミリーに応じたもの）を Read し、以下の観点で構造化評価を行う。推測・一般論ではなく、実際の関数定義・regex・Step 4 の `--explain` 出力を根拠にする:

| チェック項目 | 確認内容 |
|---|---|
| Variable expansion | `_has_variable_expansion` に該当する未引用変数展開が候補コマンドに含まれるか（`docs/L0_concept/policy.md` issue #196 の既知 bypass を考慮） |
| Absolute-path / cwd bypass | `normalize_absolute_path_prefix` / `normalize_git_directory_prefix` が想定する形を外れた絶対パス・`-C` 指定が紛れていないか |
| Unquoted write redirect | `_has_unquoted_write_redirect` に該当する書き込みリダイレクトが含まれるか |
| Destructive flags | 対象コマンドファミリーにおける破壊的フラグ（`--force`/`-f`/`-D`/`--hard` 等）が含まれるか |
| 既存 allow-shape との比較 | 最も近い既存の `is_safe_*` 関数のどの条件にマッチしないため `user_prompt` に落ちているか、無条件許可に拡張する場合の最小差分（対象関数・regex の変更点概要）を明記する。実装はしない |

上記を踏まえた **Verdict** を1つ定める:
- `already-safe`: Step 4 の `--explain` 結果が候補コマンドそのものに対して既に `approve` を返している（＝ログ記録時点以降に allow-shape が追加された、または候補コマンドが偶然すでに既存の narrow allow-shape に一致する）。ハザード分析は行わず、そのまま「対応不要」として報告するのみで issue は起票しない
- `no-known-hazard`: `--explain` が `user_prompt` を返し、かつ上記チェックで具体的な懸念が見つからず、最小限の allow-shape 拡張候補として提案できる
- `hazard-found`: `--explain` が `user_prompt` を返したが、具体的な懸念が1つ以上見つかった（理由を明記）。この候補は issue を起票しない

### Step 6: ユーザーへの一括提示・承認

全候補（`already-safe` / `no-known-hazard` / `hazard-found` 全て）を1回でまとめて提示する:

```
## Auto-Approve Hazard Scan Results (N candidates)

### No known hazard — issue 起票候補 (N)
- <pattern>: `<command>` — <1行要約>

### Hazard found — 起票しない (N)
- <pattern>: `<command>` — 懸念: <1行要約>

### Already safe — 対応不要 (N)
- <pattern>: `<command>` — 現在のコードで既に approve
```

各候補の詳細（ハザードチェックリスト全項目・`--explain` 出力・提案する allow-shape 変更）も合わせて提示する。

**ユーザーに確認する:**
「`no-known-hazard` の候補について `auto-approve-candidate` issue を起票します。よろしいですか？（yes / no / 一部のみ選択したい）」

- `no` → 起票せず終了する
- `yes` → 全ての `no-known-hazard` 候補を Step 7 で起票する
- 一部選択 → 指定された候補のみ Step 7 で起票する

### Step 7: label 確認・issue 起票

`auto-approve-candidate` label が存在しない場合（Step 3 で確認済み）、作成をユーザーに提案する:
- name: `auto-approve-candidate`
- description: `AI-proposed auto-approve allowlist extension candidate, pending human review`
- color: 任意の未使用色（例: `#0e8a16`）

承認を得てから:
```bash
gh label create --name "auto-approve-candidate" --description "AI-proposed auto-approve allowlist extension candidate, pending human review" --color "0e8a16"
```

承認された各候補について起票する（タイトル・本文は英語）:

```bash
gh issue create --title "<English title>" --label "auto-approve-candidate" --body-file - <<'EOF'
## Overview
[Proposed allow-shape extension — what command shape and why]

## Evidence
- Pattern: <pattern name>
- Log-observed frequency: <count>
- Candidate command: `<command>`
- Source: logs/auto-approve/*.log via /analyze-auto-approve (--all)

## --explain Output
```
<hooks/auto-approve-readonly.sh --explain の出力>
```

## Hazard Checklist
- Variable expansion: <PASS/該当なし の根拠>
- Absolute-path / cwd bypass: <同上>
- Unquoted write redirect: <同上>
- Destructive flags: <同上>
- Nearest existing allow-shape: <関数名と、マッチしない理由>

## Proposed Change (not implemented here)
[対象関数・regexの変更概要]

## Done Criteria
A human reviews this proposal and, if agreed, implements it via /work.
EOF
```

各作成で得られた issue 番号と URL を保持する。

### Step 8: 完了報告

```
## Auto-Approve Hazard Scan Complete

候補総数: N 件（うち重複除外: N 件）
- 起票: N 件（issue 番号・URL 一覧）
- hazard-found のため見送り: N 件（理由の要約）
- ユーザーが選択せず見送り: N 件
```

---

## スコープ外

- `hooks/auto-approve-readonly.sh` を含む既存コード・hookの変更（`/review-resolve` またはユーザーが手動で行う `/work` が担う）
- 起票した issue への `/work` の自動起動（`/triage-issues-for-auto-approve`（issue #285）または `/work #N` をユーザーが個別に呼ぶ）
- ユーザー一括承認なしの issue 自動起票
