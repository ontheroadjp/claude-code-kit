# `commands/auto-approve-hazard-scan.md` specification

## 目的・役割

`logs/auto-approve/*.log` で `user_prompt` に落ちている定型処理コマンドから allowlist 拡張候補を洗い出し、`hooks/auto-approve-readonly.sh --explain` の判定根拠をもとに AI が構造化ハザードチェックリストを作成し、既知ハザードが見つからない候補についてのみ `auto-approve-candidate` label 付き GitHub issue を起票するスタンドアロンのワークフロー。issue #282（アンブレラ）配下の issue #284 として追加された。`/work`・`/task`・`/patch`・`/new-issue`・`/triage-issues` とは独立している。

根拠: `commands/auto-approve-hazard-scan.md:1-9`

## 動作の概要

9 Step で構成される:

```
Step 0: main ブランチ確認、gh auth status 確認
Step 1: scripts/analyze_auto_approve.py --all を実行し routine_ops.patterns_needing_approval を取得
Step 2: 各パターンの sample_commands（頻度降順）上位3件を候補として抽出
Step 3: 既存の auto-approve-candidate issue（open/closed）の本文と完全一致比較し重複候補を除外
Step 4: 各候補について CLAUDE_CODE_KIT_SESSION_APPROVED_FILE=/nonexistent/... を指定して
        hooks/auto-approve-readonly.sh --explain を実行（cold-session診断）
Step 5: --explain の verdict と該当 is_safe_* 関数の実装を根拠に、
        already-safe / no-known-hazard / hazard-found のいずれかを判定
Step 6: 全候補（3分類とも）を1回でまとめて提示し、no-known-hazard 候補への
        issue起票についてユーザーの一括承認を取る
Step 7: auto-approve-candidate label が未作成なら承認を得て作成し、
        承認された候補ごとに gh issue create --label auto-approve-candidate
Step 8: 起票結果・見送り理由を報告
```

根拠: `commands/auto-approve-hazard-scan.md:13-141`

## 主要な判定ロジック・フロー

- 候補データは常に `python3 scripts/analyze_auto_approve.py --all`（全期間ログ）から取得する。単月データだと候補の見落としが生じるため
- `--explain` は実行中セッション自身の `session-approved` ファイルを fast path として参照する（`hooks/auto-approve-readonly.sh:1776`）。分析者自身のセッションが既に `tool:git_write` 等を承認済みだと、本来 `user_prompt` になるべき候補も `approve` と誤診断されるため、`CLAUDE_CODE_KIT_SESSION_APPROVED_FILE` を存在しないパスに向けて実行し、常に「新規セッションでの判定」を診断する
- ハザードチェックリストは5項目固定: variable expansion / absolute-path・cwd bypass / unquoted write redirect / destructive flags / 既存 allow-shape との比較。いずれも推測ではなく `hooks/auto-approve-readonly.sh` の該当関数の実装と `--explain` 出力を根拠にする
- Verdict は3種類:
    - `already-safe`: 候補コマンドが `--explain` で既に `approve` と判定される（ログ記録時点以降に allow-shape が追加された等）。issue 化しない
    - `no-known-hazard`: `user_prompt` かつハザード懸念なし。issue 化候補
    - `hazard-found`: `user_prompt` だが具体的懸念あり。issue 化しない
- issue 起票は「全候補をまとめて提示 → 1回のユーザー承認 → 一括起票」というバッチ承認方式を取る。個別コマンドごとの都度確認はしない（`/new-issue`・`/triage-issues` の既存慣習を踏襲）
- `auto-approve-candidate` label が存在しない場合、`gh label create` もユーザー承認を経てから実行する（`/new-issue` のラベル新規作成フローを踏襲）

根拠: `commands/auto-approve-hazard-scan.md:24-95`

## 重要な設計判断とその理由

hook 自体は一切変更しない。この command 唯一の書き込みは `gh issue create`（と初回の `gh label create`）であり、実装可否の判断とその実行は人間が `/work` を起動して行う。issue #284 の Scope に明記された「このパイプライン唯一の自動化アクションは issue 作成」という制約をそのまま踏襲した。

`--explain` の session-approved fast path を無効化する `CLAUDE_CODE_KIT_SESSION_APPROVED_FILE` オーバーライドの必要性は、コマンド設計時ではなく実データでの検証実行中に発見された。分析者自身の作業セッションが既に `tool:git_write` を承認済みの状態で `--explain` を素朴に呼ぶと、`git checkout main` や `git fetch origin main` のような本来の調査対象が「approve」と表示され、候補選定を誤らせることが判明したため、Step 4 に明記した。

`already-safe` 判定を追加したのは、検証実行で `git commit -m "..."` の narrow shape や `git add <plain paths>` が実データでは高い user_prompt 件数を記録している一方、現在のコードでは既に無条件承認されることが分かったため。これはログ記録時点以降に allow-shape が拡張された結果の「過去ログの残留ノイズ」であり、`no-known-hazard`（新規提案が必要）とも `hazard-found`（拡張すべきでない）とも異なる第三の分類が必要だった。

根拠: issue #284, `commands/auto-approve-hazard-scan.md:60-70`

## 統合ポイント

- 呼び出し元: なし（スタンドアロン entry point。ユーザーが直接起動する）
- 呼び出すもの: `scripts/analyze_auto_approve.py`（候補データ）、`hooks/auto-approve-readonly.sh --explain`（診断）
- Codex wrapper: `skills/auto-approve-hazard-scan/SKILL.md`
- 後続ワークフロー: 起票された `auto-approve-candidate` issue は `/triage-issues-for-auto-approve`（issue #285、未実装）または `/work #N` をユーザーが個別に起動して初めて実装される

## 注意事項・既知の制限

- 唯一の書き込みは `gh issue create` と（初回のみ）`gh label create`。`hooks/auto-approve-readonly.sh` を含む既存コードは変更しない
- 重複チェックは issue 本文とのコマンド文字列の完全一致でのみ行う。表記ゆれ（引用符・空白等）がある類似コマンドは重複として検出されない場合がある
- ハザードチェックリストは AI 判定であり、`hazard-found`/`already-safe` の判定漏れにより本来ハザードがある候補が `no-known-hazard` として issue 化されるリスクは残る。ただし issue は提案に過ぎず、実装（hook変更）には別途人間の `/work` 承認が必須であるため、実害は「不要な issue が増える」程度に限定される

## 変更履歴（git log より自動生成）

（初回追加のためコミット前。次回 /docs-sync 実行時に自動反映される）
