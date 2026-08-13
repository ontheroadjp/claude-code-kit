# `tests/scripts/test-rename-thread.sh`

## 目的・役割

`scripts/rename-thread.sh` が Claude Code transcript に正しい `custom-title` レコードを追記し、セッション ID がない場合は変更しないことを検証する。

根拠: `tests/scripts/test-rename-thread.sh:1-38`

## 動作の概要

一時的な working directory と Claude home を作り、固定セッション ID の transcript fixture を用意する。スクリプトを実行した後、`jq` で title、session ID、timestamp を検証する。次にセッション ID を外して再実行し、行数が変わらないことを確認する。空の title は失敗することも検証する。

根拠: `tests/scripts/test-rename-thread.sh:10-38`

## 統合ポイント

- 対象: `scripts/rename-thread.sh`
- 実行: `bash tests/scripts/test-rename-thread.sh`
