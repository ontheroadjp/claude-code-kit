# test-session-paths.sh specification

## 目的・役割

`tests/hooks/test-session-paths.sh` は `hooks/lib/session-paths.sh`（issue #316）の functional test である。session-approved/session-tmp-dir 両モードの既定 formula、オーバーライド環境変数の優先順位、symlink 経由実行、不正引数時の異常終了を検証する。

根拠: `tests/hooks/test-session-paths.sh:1-10`

## 動作の概要

一時ディレクトリを作成し、`hooks/lib/session-paths.sh` を対象スクリプトとして直接実行する。各ケースの標準出力を `assert_eq` で期待値と比較する。

根拠: `tests/hooks/test-session-paths.sh:4-20`

## 主要な判定ロジック・フロー

- `session-approved`: 既定 formula（`CLAUDE_CODE_KIT_STATE_HOME` 反映）、`CLAUDE_CODE_KIT_SESSION_DIR` オーバーライド、`CLAUDE_CODE_KIT_SESSION_APPROVED_FILE` オーバーライド（最優先）を検証する
- `session-tmp-dir`: 既定ルート（`/tmp/claude-code-kit`）、`CLAUDE_CODE_KIT_TMP_ROOT` オーバーライドを検証する
- symlink 経由実行: `~/.claude/hooks/lib/session-paths.sh` のようにインストール後の symlink 経由で呼ばれても正しく自己位置解決できることを検証する（`install.sh` が実際に作る配置を模倣）
- 引数なし・不明な引数の場合に非ゼロ終了することを検証する

根拠: `tests/hooks/test-session-paths.sh:37-100`

## 重要な設計判断

`hooks/auto-approve-readonly.sh`/`hooks/cleanup-session.sh` が既にサポートしているオーバーライド環境変数を `session-paths.sh` が正しく反映することは、`commands/*.md` インライン式が同オーバーライドを無視していたドリフトバグ（issue #316）の再発防止として特に重要なため、各オーバーライドを個別ケースとして固定した。

## 統合ポイント

- test target: `hooks/lib/session-paths.sh`
- execution: `bash tests/hooks/test-session-paths.sh`
- 関連: `tests/hooks/test-approval-hooks.sh`（`hooks/auto-approve-readonly.sh`/`hooks/cleanup-session.sh` 自体の formula を検証。本テストは `session-paths.sh` が同じ formula を再現していることを検証する）

## 注意事項・既知の制限

- CI（`.github/workflows/test.yml`）には未登録。`tests/hooks/test-approval-hooks.sh` のみが CI 対象で、本テストは他の `tests/install/`・`tests/scripts/` 配下のテストと同様、手動実行が前提

## 変更履歴（git log より自動生成）

- e7d5698 fix(#316): resolve session paths via hooks/lib/session-paths.sh to survive worktree-isolated harness guard
