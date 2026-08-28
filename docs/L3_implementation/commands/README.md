# commands/README.md — L3 per-file doc

## 目的・役割

`commands/` ディレクトリの目的・ファイル構成・ルーティング構造・使い方を開発者向けに説明するドキュメント。

## 動作の概要

- コマンド一覧を表形式で提示し、各コマンドの役割を1行で説明
- commandsをworkflow definitionのSource of Truth、Codex skillsをそのadapterとして説明
- user-controlled workflow、internal workflow / stage、supporting capabilityのinvocation authorityをL1/L2へ接続
- `/work` を頂点としたルーティング構造（mtg/task/patch への委譲）を図示
- インストール手順と呼び出し例を記載

## 重要な設計判断

- ルーティング図は ASCII art で記述し、Markdown レンダラーに依存しない
- invocation authorityはcommandの配置やUI mechanismではなくworkflow responsibilityとして扱う
- `commands/` 内の各ファイルへの詳細説明は `specification_summary.md` に委ねており、README では役割の一覧にとどめる

## 統合ポイント

- 参照元: リポジトリを初めて閲覧する開発者、`docs/L1_project/repository_structure.md`
- 関連: `commands/*.md`（各コマンドの実体）、`docs/L3_implementation/specification_summary.md`

## 注意事項

コマンド一覧が増減した場合は、このファイルのテーブルも更新すること。

agenda label の issue は人間主導の `/mtg` へ、それ以外は issue と docs 変更要否に基づいて task/patch へ進む。`/mtg` は `/new-issue` を自動実行しない。

根拠: `commands/README.md:1-79`

## 変更履歴（git log より自動生成）

- c9e5dff docs(#393): clarify project design philosophy
- 446c4d3 #343 Replace report review with human-led mtg agendas (#345)
- a46be53 feat(#321): unify operational hazard workflows
- 91067f8 docs: initialize project documentation (init-docs)
- d4bd418 feat(#267): add /coding-sh command and enforce shellcheck across all shell scripts
- 5a4ecc6 chore(#205): remove /pr-review; /work and /task now end at PR creation
- c25b25a docs(#126): add pr-review to catalogs
- 27660a1 docs(#126): document report review catalogs
- 3656e6e docs(#175): add README.md to each module directory
