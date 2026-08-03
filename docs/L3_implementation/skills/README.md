# skills/README.md — L3 per-file doc

## 目的・役割

`skills/` ディレクトリの目的・skill wrapper の仕組み・`commands/` との対応関係を開発者向けに説明するドキュメント。

## 動作の概要

- skill が `commands/*.md` を Source of Truth として Read するだけの薄い wrapper であることを説明
- ディレクトリ構造（`<name>/SKILL.md` と `<name>/work` サブディレクトリ）を図示
- skill 一覧と対応コマンドの対照表を提示
- `report-review/` を `commands/report-review.md` の read-only wrapper として掲載

## 重要な設計判断

- skill 側にはロジックを書かず、全て commands/ 側に集約するアーキテクチャを明示
- 新しいコマンドを追加した際の skill 追加手順を案内
- `install.sh` が `skills/*/` を自動検出するため、installer への個別追記は不要と明記

## 統合ポイント

- 参照元: Codex CLI ユーザー、`install.sh`（symlink 作成）
- 関連: `skills/*/SKILL.md`（各 skill の実体）、`commands/*.md`

根拠: `skills/README.md:1-60`, `skills/work/SKILL.md:1-23`, `skills/report-review/SKILL.md:1-25`

## 変更履歴（git log より自動生成）

- 5a4ecc6 chore(#205): remove /pr-review; /work and /task now end at PR creation
- c25b25a docs(#126): add pr-review to catalogs
- 27660a1 docs(#126): document report review catalogs
- 3656e6e docs(#175): add README.md to each module directory
