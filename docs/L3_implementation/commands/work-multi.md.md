# `commands/work-multi.md`

## 目的・役割

意図的に並行する `/work` 実行を、`EnterWorktree` の専用 worktree 内へ隔離して開始する。

根拠: `commands/work-multi.md:1-57`

## 動作の概要

元の working tree を記録して `EnterWorktree` へ切り替え、installed linker の `prepare` で source path と空 manifest を current session に記録する。この段階では symlink を作らない。作業中に必要になった untracked/ignored path だけを linker の `link <relative-path>` で作成する。lazy link した path は読み取り専用であり、書き込みが必要な path は link 前に worktree 内へ独立して作成する。その後は `commands/work.md` を一字一句そのまま実行する。親 issue の検出と次に実行すべき子 issue の報告・終了も `work.md` に一元化される。後続の status helper は manifest に記録された自己作成 symlink だけを自動除外する。

根拠: `commands/work-multi.md:16-52`

## 重要な設計判断

開始時に全 untracked/ignored path を link せず、必要性が確定した path だけを link する。`node_modules` のような大きな ignored directory を使わない issue のセットアップコストを抑えるため。

lazy symlink は元 working tree への書き込み経路にもなるため、単独・並行を問わず読み取り用途に限定する。書き込みが必要な path を worktree 内へ独立作成することで、元 working tree の変更と共有可変状態の競合を防ぐ。

## 統合ポイント

- 呼び出すもの: `EnterWorktree`、agent 別 `link-worktree-untracked.sh`、`commands/work.md`
- 関連: `scripts/worktree-status.sh` が linker manifest を利用する

## 注意事項・既知の制限

lazy link した path への書き込みは禁止する。worktree を削除しても、symlink 経由で元 working tree に書き込まれた変更は戻らない。

## 変更履歴（git log より自動生成）

- 314fbc1 docs(#334): clarify worktree symlink write isolation
- 5f7ba97 feat(#328): add lazy worktree linker
- ea565ac #326 Automate worktree symlink status filtering (#327)
- 4f4aab8 #324 Install the worktree linker for consumer repositories (#325)
- 1aa3c2d fix(#318): distinguish worktree-untracked symlinks from real changes via manifest
- bc4ae7b feat(#296): add /work-multi worktree-isolated entry point
