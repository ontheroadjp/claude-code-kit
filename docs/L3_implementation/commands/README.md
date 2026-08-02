# commands/README.md — L3 per-file doc

## 目的・役割

`commands/` ディレクトリの目的・ファイル構成・ルーティング構造・使い方を開発者向けに説明するドキュメント。

## 動作の概要

- コマンド一覧を表形式で提示し、各コマンドの役割を1行で説明
- `/work` を頂点としたルーティング構造（report-review/task/patch への委譲）を図示
- インストール手順と呼び出し例を記載

## 重要な設計判断

- ルーティング図は ASCII art で記述し、Markdown レンダラーに依存しない
- `commands/` 内の各ファイルへの詳細説明は `specification_summary.md` に委ねており、README では役割の一覧にとどめる

## 統合ポイント

- 参照元: リポジトリを初めて閲覧する開発者、`docs/L1_project/repository_structure.md`
- 関連: `commands/*.md`（各コマンドの実体）、`docs/L3_implementation/specification_summary.md`

## 注意事項

コマンド一覧が増減した場合は、このファイルのテーブルも更新すること。

report label の issue は read-only `/report-review` へ、それ以外は issue と docs 変更要否に基づいて task/patch へ進む。コマンド一覧にも report-review の標準出力専用評価という責務を記載する。

根拠: `commands/README.md:1-61`

## 変更履歴（git log より自動生成）

- 3656e6e docs(#175): add README.md to each module directory
