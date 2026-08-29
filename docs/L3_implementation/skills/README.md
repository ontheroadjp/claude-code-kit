# skills/README.md — L3 per-file doc

## Unified workflow adapters

`work/` は単一・複数 issue の session owner、`task/` は ordinary/delegated 共通の issue-specific implementation adapter、`task-manager/` は valid `/work` handoff でのみ起動する internal orchestrator adapter として catalog 化される。

根拠: `skills/README.md:29-40`

## 目的・役割

`skills/` ディレクトリの目的・skill wrapper の仕組み・`commands/` との対応関係を開発者向けに説明するドキュメント。

## 動作の概要

- skill が `commands/*.md` を Source of Truth として Read するだけの薄い wrapper であることを説明
- user-controlled workflow の wrapper は明示的な user request で開始し、internal workflow / stage や supporting capability と同じ権限で自発的に開始しないことを説明
- ディレクトリ構造（`<name>/SKILL.md` と `<name>/work` サブディレクトリ）を図示
- skill 一覧と対応コマンドの対照表を提示
- `mtg/` を `commands/mtg.md` の人間主導の対話 wrapper として掲載
- `git-pr-merge/` をreview済みPR deliveryのwrapperとして掲載
- 現行28 skillと対応commandのcatalogを掲載

## 重要な設計判断

- skill 側にはロジックを書かず、全て commands/ 側に集約する。wrapper は workflow の開始権限や手順を再解釈しない adapter であることを明示
- 新しいコマンドを追加した際の skill 追加手順を案内
- `install.sh` が `skills/*/` を自動検出するため、installer への個別追記は不要と明記

## 統合ポイント

- 参照元: Codex CLI ユーザー、`install.sh`（symlink 作成）
- 関連: `skills/*/SKILL.md`（各 skill の実体）、`commands/*.md`

根拠: `skills/README.md:1-76`, `skills/work/SKILL.md:1-22`, `skills/git-pr-merge/SKILL.md:1-25`

## 変更履歴（git log より自動生成）

- c9e5dff docs(#393): clarify project design philosophy
- a23fda3 #389 Add reusable reviewed PR delivery workflow (#391)
- 446c4d3 #343 Replace report review with human-led mtg agendas (#345)
- a46be53 feat(#321): unify operational hazard workflows
- 91067f8 docs: initialize project documentation (init-docs)
- d4bd418 feat(#267): add /coding-sh command and enforce shellcheck across all shell scripts
- 5a4ecc6 chore(#205): remove /pr-review; /work and /task now end at PR creation
- c25b25a docs(#126): add pr-review to catalogs
- 27660a1 docs(#126): document report review catalogs
- 3656e6e docs(#175): add README.md to each module directory
