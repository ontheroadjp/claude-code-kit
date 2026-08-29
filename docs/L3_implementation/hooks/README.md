# hooks/README.md — L3 per-file doc

## 目的・役割

`hooks/` ディレクトリの目的・hook 種別・イベントマッピング・インストール方法を開発者向けに説明するドキュメント。

## 動作の概要

- Claude Code / Codex CLI のイベント（PreToolUse / PostToolUse / UserPromptSubmit / Notification / Stop）と hook の対応表を提示
- 各 hook ファイルの役割を一行で説明
- `auto-approve-readonly.sh` の承認フローを概略図で示す
- tmux ステータス表示の設定方法を記載

## 重要な設計判断

- 承認フローの詳細は `docs/L3_implementation/hooks/auto_approve_readonly.md` に委ねており、README では概略のみ記載
- `notify-slack.sh` は Notification / Stop event に登録される通知 hook として分類

## 統合ポイント

- 参照元: リポジトリを初めて閲覧する開発者、`docs/L1_project/repository_structure.md`
- 関連: `hooks/*.sh`（各 hook の実体）、`hooks/lib/approval-safety.sh`

## 注意事項

hook を追加した場合は、イベントマッピング表とファイル一覧テーブルを更新すること。

根拠: `hooks/README.md:1-60`, `install.sh:165-186`

## 変更履歴（git log より自動生成）

- 3656e6e docs(#175): add README.md to each module directory

## Work-run correlation

work-run eventの `agent_session_id` はaccess・auto-approval・token-usage logsと同じresolverに基づくjoin keyである。既存log内容はJSONLへ複製せず、固定schemaのidentifier/state/resultだけを記録する。

根拠: `hooks/README.md:35-39`
