# /new-issue specification

## 目的・役割

`commands/new-issue.md` は rough idea を実装可能な GitHub issue に整形する任意の pre-`/work` workflow である。実装や branch 操作は行わない。

根拠: `commands/new-issue.md:1-10`

## 動作の概要

ユーザーから背景・制約・完了条件を取得し（Step 2 では明確化のみ行い、個別の内容確認は求めない）、Step 3 でスコープ分割方針を4択（分割しない／Phase分割／親子issue分割／単体分割）からユーザーが決定した後、Step 4 でドラフトとラベル（既存採用 or 新規案）をまとめて一度に提示し、単一承認を得て GitHub issue を作成する。

根拠: `commands/new-issue.md:18-162`

## 主要な判定ロジック

- template root は実行 agent ごとに切り替える。Claude Code は `~/.claude/templates`、Codex CLI は `~/.codex/templates` を `TEMPLATES_DIR` とし、`${TEMPLATES_DIR}/issue.md` を利用する。
- Step 3 の選択肢 [3]（親子issue として分割）を選んだ場合、親子関係は GitHub の native sub-issue だけで管理する。親issue本文は親の目的・全体の完了条件・子issueに共通する制約を記載し、子issue一覧や GitHub task list 記法（`- [ ] #<子issue番号>`）は記載しない。
- Step 5 では親issueを先に作成し、次に子issueを全件作成して、各子issueを親issueの native sub-issue として紐付ける。親子関係は native sub-issue を source of truth とするため、子issueへの親参照コメントは投稿しない。
- Step 4（issue #301）: ラベル選定（既存ラベル選定 or 新規ラベル案の準備）はドラフト提示より前に行う。standalone 起動時は、全ドラフト（タイトル・本文）と選定・提案ラベルをまとめて一度に提示し、単一の承認で「ドラフト内容」「ラベル（採用/新規作成）」「`gh issue create` の実行」をまとめて認可する。承認後、session-approved に `tool:gh_issue_write:0`（`create` は N を検査しないためプレースホルダで機能する）、新規ラベルが必要な場合は `tool:gh_label_write` も書き込み、以降の `gh issue create`/`gh label create` の実行確認を不要にする。
- `commands/task.md` が Step 4〜5 のみを呼び出す経路（issue 自動生成）では、task.md 自身のプラン承認・session-approved 書き込みと二重にならないよう、この「提示・単一承認」を丸ごとスキップする。この経路での新規ラベル作成は task.md の session-approved に `tool:gh_label_write` が含まれない限り通常の確認プロンプトに従う。

根拠: `commands/new-issue.md:12-14`, `commands/new-issue.md:45-65`, `commands/new-issue.md:67-126`, `commands/new-issue.md:146-152`, issue #301

## 重要な設計判断

- template の source of truth は repository に保持し、agent 固有の installed path から symlink 経由で読む。これにより command 自体は両 agent で共有しつつ、各 runtime の設定 root に閉じた参照を使える。
- 親子issueの関係と進捗追跡は GitHub の native sub-issue に一本化する。本文の Markdown task list や子issueコメントにも同じ関係を重複して記録すると、表示順・対象・進捗がずれる運用上の不整合を招くためである。
- Step 2 の内容確認と Step 4 のドラフト確認という2段階の chat 確認、および `gh issue create` 実行時のハーネス許可プロンプトという計3段階の確認が redundant だったため（issue #301）、ラベル選定を Step 4 のドラフト提示より前に前倒しし、ドラフト・ラベル・実行を単一の承認に統合した。実行確認（ハーネスのツール許可プロンプト）は `task.md`/`patch.md` と同じ session-approved 機構（`tool:gh_issue_write:<N>`）を `/new-issue` にも導入することで解消した。`tool:gh_issue_write` は他フローでは対象 issue 番号 N にスコープされるが、`/new-issue` の standalone 起動時点では issue がまだ存在せず、かつ `create` 自体は N を検査しないため、プレースホルダ値（`0`）で成立する。
- 新規ラベル作成（`gh label create`）は `tool:gh_issue_write` の対象外（issue write とは異なる GitHub リソース）のため、`hooks/auto-approve-readonly.sh` に新規の bare category `tool:gh_label_write` を追加した（対象番号を持たないため `tool:git_write` と同様に無条件承認）。

## 統合ポイント

- optional predecessor: `/work`
- optional caller: `commands/task.md`（Step 4〜5 のみを呼び出す issue 自動生成経路）
- template: `${TEMPLATES_DIR}/issue.md`
- GitHub: `gh label list`, `gh label create`, `gh issue create`、native sub-issue の親子紐付け
- session-approved: `hooks/lib/session-paths.sh session-approved` で解決したパスへ `tool:gh_issue_write:<N>`（および必要な場合 `tool:gh_label_write`）を書き込み、`hooks/auto-approve-readonly.sh` の `check_session_approved` が参照する

## 注意事項・既知の制限

- scope 分割はユーザー決定が必須
- issue title/body は英語
- `/work` を自動実行しない
- native sub-issue を作成できない GitHub 環境では、親子issue化を完了させずエラーを報告する。Markdown task list や子issueコメントへフォールバックしてはならない
- `/task` からの Step 4〜5 呼び出し経路で新規ラベルが必要になった場合、`gh label create` は task.md の session-approved に `tool:gh_label_write` を含めない限り通常の確認プロンプトに従う（既存挙動を維持、regression ではない）

## 変更履歴（git log より自動生成）

- e1354ac feat(#338): use native sub-issues for tracking
- 880ee07 feat(#301): consolidate /new-issue draft/label/creation approval into Step 4
- ff477c0 feat(#310): add parent/child issue split option to /new-issue
- 27f1861 feat(#76): install templates for claude and codex
- aeb0dc4 docs: remove environment-specific cli notes
- 25a1e8d feat(#77): add label selection step to /new-issue workflow
- 03e70dc feat(#72): simplify Step 3 options and add Claude recommendation in /new-issue
- bc2900f feat(#63): add /new-issue skill for idea-to-issue workflow
