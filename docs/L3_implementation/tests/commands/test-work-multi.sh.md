# `tests/commands/test-work-multi.sh`

## 目的・役割

`commands/work-multi.md` が `EnterWorktree` 呼び出しと `commands/work.md` への委譲のみで構成され、`work.md` のゲート定義を重複していないこと、および `commands/work.md`・`scripts/link-worktree-untracked.sh` 側の対応する改修（worktree パスガード、`worktree-` prefix ベースの (A)/(B) 判定、`.git`/`.claude` 除外）が実際に入っていることを静的に検証する shell test（issue #296、PR #304 レビューで assertion を更新）。

根拠: `tests/commands/test-work-multi.sh:1-51`

## 動作概要

固定文字列の存在・不在を検査する helper（`assert_contains`/`assert_absent`）と実行権限を検査する helper（`assert_executable`）を使い、以下を確認する。

- `commands/work-multi.md` が `EnterWorktree`・agent 別 installed path（`~/.claude/scripts/` と `~/.codex/scripts/`）・`commands/work.md` への言及を含み、consumer repo 相対の `bash scripts/link-worktree-untracked.sh` を含まず、`### G-0`/`### G-1`/`### G-2` を重複定義していない
- `skills/work-multi/SKILL.md` が `skills/work/SKILL.md` と同じ scope guard パターンを持つ
- `commands/work.md` が `.claude/worktrees/` パスガードと `worktree-` prefix ベースのブランチ分類、B.1（未コミット変更があれば継続）の保持を含む
- `scripts/link-worktree-untracked.sh` が実行権限を持ち、`status --porcelain -z --ignored=matching` による NUL 区切り列挙と `.git`/`.claude` 除外を含む

根拠: `tests/commands/test-work-multi.sh:53-76`

## 重要な設計判断

Markdown workflow は直接実行可能なプログラムではないため、`tests/commands/test-report-review.sh` と同じ static-assertion 形式を踏襲し、安全上・設計上重要な必須句の存在を contract として固定する。

## 統合ポイント

- 対象: `commands/work.md`、`commands/work-multi.md`、`skills/work/SKILL.md`、`skills/work-multi/SKILL.md`、`scripts/link-worktree-untracked.sh`
- 実行: `bash tests/commands/test-work-multi.sh`

## 注意事項・既知の制限

静的検査であり、`EnterWorktree` を実際に呼び出す end-to-end 検証は行わない（`tests/scripts/test-link-worktree-untracked.sh` が symlink 挙動自体の functional test を担う）。workflow 文面変更時は同じ意味を保持したまま assertion も更新する必要がある。

## 変更履歴（git log より自動生成）

- bc4ae7b feat(#296): add /work-multi worktree-isolated entry point
