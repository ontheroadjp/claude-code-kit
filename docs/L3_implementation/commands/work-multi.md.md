# `commands/work-multi.md`

## 目的・役割

意図的に並行する `/work` 実行を、`EnterWorktree` の専用 worktree 内へ隔離して開始する。

根拠: `commands/work-multi.md:1-57`

## 動作の概要

元の working tree を記録して `EnterWorktree` へ切り替え、installed linker で untracked/ignored path を symlink する。その後は `commands/work.md` を一字一句そのまま実行する。linker が session manifest を作成できる場合、後続の status helper が自己作成 symlink を自動除外する。

根拠: `commands/work-multi.md:16-52`

## 重要な設計判断

worktree 切り替え以外のロジックを重複定義せず、status 判定も `/work` と同じ共通ヘルパーへ委譲する。通常 `/work` と隔離実行で workflow の意味が変わらないようにするため。

## 統合ポイント

- 呼び出すもの: `EnterWorktree`、agent 別 `link-worktree-untracked.sh`、`commands/work.md`
- 関連: `scripts/worktree-status.sh` が linker manifest を利用する

## 注意事項・既知の制限

symlink 先の `node_modules` 等へ複数セッションが同時書き込みすると、共有可変状態の競合は防げない。
