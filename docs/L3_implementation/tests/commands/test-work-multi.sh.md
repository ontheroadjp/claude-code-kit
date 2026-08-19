# `tests/commands/test-work-multi.sh`

## 目的・役割

`commands/work-multi.md` が `EnterWorktree` 呼び出しと `commands/work.md` への委譲で構成され、親 issue の子 issue 依存関係判定を `work.md` に一元化していること、および worktree path guard・`worktree-` prefix 判定・linker の `.git`/`.claude` 除外・共通 status helper への委譲が実際に入っていることを静的に検証する shell test。

根拠: `tests/commands/test-work-multi.sh:1-51`

## 動作概要

固定文字列の存在・不在を検査する helper（`assert_contains`/`assert_absent`）と実行権限を検査する helper（`assert_executable`）を使い、以下を確認する。

- `commands/work-multi.md` が `EnterWorktree`・agent 別 installed path（`~/.claude/scripts/` と `~/.codex/scripts/`）・`commands/work.md` への言及を含み、consumer repo 相対の `bash scripts/link-worktree-untracked.sh` を含まず、`### G-0`/`### G-1`/`### G-2` を重複定義していない
- `ORIGINAL_WORKDIR` を Step 0.3 の linker `prepare` 引数だけに使い、共有 checkout への `cd` / `git -C` を行わず、Read・調査・Git 操作を隔離 worktree から実行することを明記している
- lazy link した path を読み取り専用として扱い、symlink 経由の書き込みを禁止し、書き込みが必要な path を worktree 内へ独立作成するよう明記している
- venv/.venv だけは `link` ではなく `venv <relative-path>` サブコマンドの使用例・basename/既存path/`.gitignore` 制約・`venv` 実体は書き込み境界の対象外である旨を明記している（issue #374）
- `scripts/link-worktree-untracked.sh` が `venv`/`.venv` basename 制限、`uv` の利用、`.gitignore` 事前検証、`uv venv` による構築を実装している
- `work-multi` 自身は親 issue の依存関係を重複取得せず `work.md` へ委譲し、`work.md` が native `subIssues` と未完了 task list を収集して、native `blockedBy` が全て `CLOSED` の最初の open 子 issue を報告のみして終了すること
- `skills/work-multi/SKILL.md` が `skills/work/SKILL.md` と同じ scope guard パターンを持つ
- `commands/work.md` が `.claude/worktrees/` パスガードと `worktree-` prefix ベースのブランチ分類、B.1（未コミット変更があれば継続）の保持を含む
- `scripts/link-worktree-untracked.sh` と `scripts/worktree-status.sh` が実行権限を持ち、前者が NUL 区切り列挙と `.git`/`.claude` 除外を行い、後者が linker manifest を読む

根拠: `tests/commands/test-work-multi.sh:53-112`

## 重要な設計判断

Markdown workflow は直接実行可能なプログラムではないため、`tests/commands/test-report-review.sh` と同じ static-assertion 形式を踏襲し、安全上・設計上重要な必須句の存在を contract として固定する。

## 統合ポイント

- 対象: `commands/work.md`、`commands/work-multi.md`、`skills/work/SKILL.md`、`skills/work-multi/SKILL.md`、`scripts/link-worktree-untracked.sh`
- 実行: `bash tests/commands/test-work-multi.sh`

## 注意事項・既知の制限

静的検査であり、`EnterWorktree` を実際に呼び出す end-to-end 検証は行わない（`tests/scripts/test-link-worktree-untracked.sh` が symlink 挙動自体の functional test を担う）。workflow 文面変更時は同じ意味を保持したまま assertion も更新する必要がある。

## 変更履歴（git log より自動生成）

- fa82b85 feat(#374): build venv/.venv via uv in /work-multi worktrees instead of lazy-linking
- f484a2d Route parent issues to their next ready child (#351)
- 6f0a4d8 #334 Document worktree symlink write isolation (#335)
- aeec3ff #332 Select ready child issues in work-multi (#333)
- 095ec20 Preserve worktree isolation in work-multi (#331)
- e624ef2 #328 Add lazy worktree linker (#329)
- ea565ac #326 Automate worktree symlink status filtering (#327)
- 4f4aab8 #324 Install the worktree linker for consumer repositories (#325)
- 69c1e80 fix(#296): use worktree- prefix only for branch classification and NUL-delimited untracked enumeration
- bc4ae7b feat(#296): add /work-multi worktree-isolated entry point
