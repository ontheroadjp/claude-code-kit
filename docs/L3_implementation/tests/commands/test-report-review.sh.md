# `tests/commands/test-report-review.sh`

## 目的・役割

`/work` から `/report-review` への routing と、report-review workflow の read-only contract を静的に検証する shell test。

根拠: `tests/commands/test-report-review.sh:1-10`, `tests/commands/test-report-review.sh:38-60`

## 動作概要

固定文字列の存在・不在を検査する helper を使い、以下を確認する。

- `/work` が issue labels を取得し、exact `report` label で report-review に委譲する
- 既存 task / patch routing が残っている
- report-review が issue context を取得し、Facts、Opinions、Proposals、Risks and Unknowns を出力する
- file / GitHub changes を禁止している
- issue / PR write、commit、push の実行 command を含まない
- Codex skill が command source of truth と read-only boundary を保持する
- commands / skills の module README が report-review を一覧に含み、skill の自動 symlink を正しく説明する

根拠: `tests/commands/test-report-review.sh:14-65`

## 重要な設計判断

Markdown workflow は直接実行可能なプログラムではないため、安全上重要な必須句と書き込み command の不在を contract として固定する。

## 統合ポイント

- 対象: `commands/work.md`、`commands/report-review.md`、`commands/README.md`、`skills/report-review/SKILL.md`、`skills/README.md`
- 実行: `bash tests/commands/test-report-review.sh`

## 注意事項・既知の制限

静的検査であり、GitHub API を使った end-to-end routing は実行しない。workflow 文面変更時は同じ意味を保持したまま assertion も更新する必要がある。

`assert_contains` に渡す期待値文字列はドキュメントの日本語抜粋を単一引用符でそのまま埋め込んでいる（`` `report` `` 等のバッククォートを含む）。ShellCheck SC2016 の誤検知対象のため、ファイル先頭（`set -euo pipefail` の前）に file-wide directive で抑制している（issue #267）。

## 変更履歴（git log より自動生成）

- d4bd418 feat(#267): add /coding-sh command and enforce shellcheck across all shell scripts
- 27660a1 docs(#126): document report review catalogs
- 0297a81 feat(#126): add report review workflow

根拠: `tests/commands/test-report-review.sh:40-72`
