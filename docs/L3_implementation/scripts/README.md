# scripts/README.md — L3 per-file doc

## 目的・役割

`scripts/` ディレクトリの目的・各スクリプトの機能と使い方を説明するドキュメント。

## 動作の概要

- `statusline.sh`: stdin JSON からコンテキスト使用率とレートリミット情報を抽出して表示
- `show-token-usage.sh`: `~/.claude/token-usage.log` を集計し、複数の表示モードで可視化
- `link-worktree-untracked.sh`: `EnterWorktree` が作成した worktree に、元の working tree の untracked/ignored ファイル・ディレクトリを symlink する（`/work-multi` から呼ばれる、issue #296）
- `rename-thread.sh`: Claude Code のセッション transcript に `custom-title` を記録し、会話スレッド名を更新する（`/task`・`/patch` から呼ばれる）

## 重要な設計判断

- `statusline.sh` は `scripts/setup_statusline_for_claude.sh` 経由でセットアップする（直接編集不要）
- `show-token-usage.sh` のデータソースは `hooks/log-token-usage.sh` が生成するログファイルに依存
- `link-worktree-untracked.sh` の設計判断の詳細は `docs/L3_implementation/scripts/link-worktree-untracked.sh.md` を参照
- `rename-thread.sh` は Claude Code のセッション ID と現在の working directory から transcript を特定する。Claude Code 外または transcript 不在時は何も変更せず終了するため、呼び出し元の作業フローを妨げない

## 統合ポイント

- `statusline.sh` セットアップ: `scripts/setup_statusline_for_claude.sh`（symlink + settings 登録）
- `show-token-usage.sh` データソース: `hooks/log-token-usage.sh`（Stop hook）→ `~/.claude/token-usage.log`
- `link-worktree-untracked.sh` 呼び出し元: `commands/work-multi.md` Step 0.3
- `rename-thread.sh` 呼び出し元: `commands/task.md`、`commands/patch.md`

根拠: `scripts/README.md:1-45`, `scripts/setup_statusline_for_claude.sh:6-57`, `scripts/statusline.sh:10-83`

## 変更履歴（git log より自動生成）

- 3aff0cc feat(#410): consolidate the shared work-run event contract into work.md
- 9fc5b9a feat(#401): add structured work run observability (#403)
- 0bc7683 #344 Add a thread-renaming helper (#346)
- bc4ae7b feat(#296): add /work-multi worktree-isolated entry point
- d7a7627 feat(#212): add /analyze-access, /analyze-auto-approve, /analyze-token-usage log analysis commands
- 3656e6e docs(#175): add README.md to each module directory

## Work-run tools

- `work-run-events.sh`: logical `/work` runのprivacy-preserving semantic eventをper-run JSONLへ記録するfail-open writer。event/key の正準は `allowed_event()` / `allowed_key()`、caller 側の契約は `commands/work.md`「Work-run observability › 共有契約」を参照。
- `analyze_work_runs.py`: status、elapsed/approval/PR preparation/delivery time、parallel worker peak、issue/session correlationを集計するread-only analyzer。

根拠: `scripts/README.md:11-22`
