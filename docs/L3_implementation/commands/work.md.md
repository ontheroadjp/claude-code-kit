# `commands/work.md`

## 目的・役割

`/work` の共通入口として、workspace の安全な開始状態を確認し、親 issue であれば次に実行すべき子 issue を報告して終了し、それ以外を `/task` または `/patch` へルーティングする。`/work-multi` の worktree 内でも同じ仕様を実行する。

根拠: `commands/work.md:1-214`

## 動作の概要

G-0 で通常 worktree と `EnterWorktree` 作成 worktree を区別して main checkout を安全に扱い、G-1 で repository profile を確認する。G-2 では agent 別に配布された `worktree-status.sh` を実行して workspace 状態を判定する。このヘルパーは通常実行では `git status --porcelain` と同じ結果を返し、隔離 worktree の current session manifest が存在するときだけ、linker が作成した symlink を除外する。issue 番号が指定された場合は、label 判定より先に native `subIssues` と未完了 task list から子 issue を収集し、open かつ native `blockedBy` が全て closed の最初の子 issue を報告して終了する。子 issue は自動実装しない。

根拠: `commands/work.md:9-60`

## 重要な設計判断

- self-created symlink の manifest 照合を workflow 文面の手作業にせず、共通ヘルパーへ集約する。G-2 と `/task` Phase 2 の判定差を防ぎ、繰り返しの推論を不要にするため。
- manifest がない場合は status を変更しない。`/work` 単体利用と、helper 未配布の既存環境を後方互換に保つため。

## 統合ポイント

- 呼び出し元: `/work`、`/work-multi` Step 1
- 呼び出すもの: agent 別 `scripts/worktree-status.sh`、`commands/task.md`、`commands/patch.md`
- 関連: `scripts/link-worktree-untracked.sh` が session manifest を生成する

## 注意事項・既知の制限

manifest に記録されない untracked path は、worktree 内でも実際の差分として扱う。

親 issue の子 issue 選択は native dependency を唯一の根拠とする。dependency の取得に失敗した場合や実装可能な子 issue がない場合は、推測せず状況を報告して終了する。
