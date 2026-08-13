# `commands/work-multi.md`

## 目的・役割

意図的に並行する `/work` 実行を、`EnterWorktree` の専用 worktree 内へ隔離して開始する。

根拠: `commands/work-multi.md:1-57`

## 動作の概要

元の working tree を記録して `EnterWorktree` へ切り替え、installed linker の `prepare` で source path と空 manifest を current session に記録する。この段階では symlink を作らない。作業中に必要になった untracked/ignored path だけを linker の `link <relative-path>` で作成する。その後は `commands/work.md` を一字一句そのまま実行する。後続の status helper は manifest に記録された自己作成 symlink だけを自動除外する。

根拠: `commands/work-multi.md:16-52`

## 重要な設計判断

開始時に全 untracked/ignored path を link せず、必要性が確定した path だけを link する。`node_modules` のような大きな ignored directory を使わない issue のセットアップコストを抑えるため。

## 統合ポイント

- 呼び出すもの: `EnterWorktree`、agent 別 `link-worktree-untracked.sh`、`commands/work.md`
- 関連: `scripts/worktree-status.sh` が linker manifest を利用する

## 注意事項・既知の制限

lazy link した `node_modules` 等へ複数セッションが同時書き込みすると、共有可変状態の競合は防げない。
