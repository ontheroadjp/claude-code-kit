# `commands/git-commit.md` specification

## 目的・役割

`/git-commit` は作業ブランチの staged diff を確認し、Conventional Commits 形式の commit を作成する。呼び出し元から issue number、許可する type、または fixed message を受け取る。

根拠: `commands/git-commit.md:1-15`

## WIP commit の正規化

HEAD の subject が `wip:` で始まる場合、first-parent 上の連続 WIP range を調べ、その直前の non-WIP commit へ `git reset --soft <hash>` する。WIP range の差分は staged のまま保たれるため、最終的な Conventional Commit にまとめられる。連続 range より前の WIP commit は対象外である。

この reset は `hooks/auto-approve-readonly.sh` の `is_wip_squash_soft_reset()` が現在履歴と target hash を照合して自動承認する。条件に一致しない reset は通常の許可フローに戻り、hard reset は destructive guard が block する。

根拠: `commands/git-commit.md:25-54`, `hooks/auto-approve-readonly.sh:1269-1294`

## commit 作成

staged diff が空なら中止する。個人情報、IP address、domain name、absolute path を確認したあと、fixed message がなければ許可 type から1つ選び、issue number があれば `<type>(#N): <description>`、なければ `<type>: <description>` の形式で commit する。pre-commit hook が失敗した場合は `--no-verify` または修正をユーザーに選ばせる。

根拠: `commands/git-commit.md:56-104`

## 変更履歴（git log より自動生成）

- 8aeaa64 feat(#352): auto-approve WIP squash resets
- f979a97 fix(#159): squash only contiguous WIP commits at HEAD instead of resetting to merge-base
- 89d5fad feat(#157): move git-commit to commands/, add skill wrapper, update all callers to /git-commit
