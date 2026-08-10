# /new-issue specification

## 目的・役割

`commands/new-issue.md` は rough idea を実装可能な GitHub issue に整形する任意の pre-`/work` workflow である。実装や branch 操作は行わない。

根拠: `commands/new-issue.md:1-10`

## 動作の概要

ユーザーから背景・制約・完了条件を取得し、Step 3 でスコープ分割方針を4択（分割しない／Phase分割／親子issue分割／単体分割）からユーザーが決定した後、issue template に沿った英語 draft を確認して GitHub issue を作成する。

根拠: `commands/new-issue.md:18-135`

## 主要な判定ロジック

- template root は実行 agent ごとに切り替える。Claude Code は `~/.claude/templates`、Codex CLI は `~/.codex/templates` を `TEMPLATES_DIR` とし、`${TEMPLATES_DIR}/issue.md` を利用する。
- Step 3 の選択肢 [3]（親子issue として分割）を選んだ場合、親issue本文の Scope (initial estimate) セクションを GitHub task list 記法（`- [ ] #<子issue番号>`）に置き換える。GitHub は task list 内で参照した issue が close されると当該行のチェックボックスを自動でオンにするネイティブ機能を持つため、これに乗るだけで進捗追跡が成立し、子issue側に手動チェック手順は書かない。
- 親issueは子issue番号を本文に含める必要があるため、Step 5 では子issueを先に全件作成してから親issueを作成する（逆順は不可）。親issue作成後、各子issueに `gh issue comment` で親issue番号を1行コメントとして投稿し、双方向に参照できるようにする。

根拠: `commands/new-issue.md:12-14`, `commands/new-issue.md:45-65`, `commands/new-issue.md:76-81`, `commands/new-issue.md:119-125`

## 重要な設計判断

- template の source of truth は repository に保持し、agent 固有の installed path から symlink 経由で読む。これにより command 自体は両 agent で共有しつつ、各 runtime の設定 root に閉じた参照を使える。
- 親子issueの進捗追跡は独自のチェック機構を実装せず、GitHub 標準の task list 自動チェック機能にそのまま乗る設計にした。子issue側に手動でチェックを入れる手順を持たせると、close 忘れ・チェック漏れという新たな失敗モードが増えるため、既存のネイティブ機能で代替できる範囲は代替する（issue #310、#295/#307/#308/#309 での実運用が根拠）。

## 統合ポイント

- optional predecessor: `/work`
- template: `${TEMPLATES_DIR}/issue.md`
- GitHub: `gh label list`, `gh issue create`, `gh issue comment`（親子issue化時の相互参照コメント）

## 注意事項・既知の制限

- scope 分割はユーザー決定が必須
- issue title/body は英語
- `/work` を自動実行しない
- 親子issueの自動チェックは同一リポジトリ内の `#<番号>` 参照が前提の GitHub 標準機能であり、`/new-issue` 側で明示的に検証・保証しているわけではない

## 変更履歴（git log より自動生成）

- ff477c0 feat(#310): add parent/child issue split option to /new-issue
- 27f1861 feat(#76): install templates for claude and codex
- aeb0dc4 docs: remove environment-specific cli notes
- 25a1e8d feat(#77): add label selection step to /new-issue workflow
- 03e70dc feat(#72): simplify Step 3 options and add Claude recommendation in /new-issue
- bc2900f feat(#63): add /new-issue skill for idea-to-issue workflow
