# Operation Model

## コマンド使い分けの判定ロジック

ユーザーは常に `/task` を呼ぶ。`task.md` 内部でルーティング判定を行い、patch フローまたは task フローを実行する。

**判定基準（単一質問）:**
「この変更の結果として、`docs/*` に対して追加・変更・削除のいずれかが必要になるか？」

- → 変わらない場合: patch フロー（branch + commit、issue/PR なし）
- → 変わる場合: task フロー（issue → 実装 → ドラフト PR → /docs-sync）

根拠: `task.md:37-86`（ルーティング判定・patch フロー）

## ワークフロー概要

### 軽微な修正（patch フロー）
```
/task 呼び出し
→ ルーティング判定（docs 変更不要）
→ branch 作成（patch/<slug>）
→ 変更・コミット
→ ユーザーが main へ ff-merge
```
根拠: `task.md:61-86`

### ドキュメントを伴う実装（task フロー）
```
/task 呼び出し
→ ルーティング判定（docs 変更あり）
→ issue 確認/自動生成
→ Step1: 現状調査
→ Step2: プラン策定（ユーザー許可必須）
→ Step3: 実装・WIP コミット
→ Phase 2: ドラフト PR 作成（templates/pr.md 使用）
→ /docs-sync 呼び出しへ引き継ぎ
```
根拠: `task.md:115-204`

### ドキュメント同期（/docs-sync）
```
/docs-sync 呼び出し
→ git diff --name-only で変更ファイル確定
→ HARD STOP 判定（全体再構築が必要か）
→ 対象 docs を最小更新
→ ドラフト PR を公開（ready）
```
根拠: `docs-sync.md:各所`

### ドキュメント全体再構築（/init-docs）
再実行トリガー:
- `/docs-sync` が HARD STOP を検知した場合
- docs が現状を説明できなくなった場合
- 新規レイヤ導入・エントリポイント変更の疑いがある場合

根拠: `init-docs.md:9-19`

## ゲート設計

| コマンド | G-1 | G-2 | G-3 |
|----------|-----|-----|-----|
| task.md | docs/.ai/repo.profile.json 必須 | main かつクリーン（stash） | - |
| patch.md | docs/.ai/repo.profile.json 必須 | main ブランチにいること | クリーン（stash） |
| docs-sync.md | docs/.ai/repo.profile.json 必須 | main 以外のブランチ | WIP コミット存在 |
| init-docs.md | .git/ 必須 | - | - |

根拠: `task.md:23-32`, `patch.md:11-24`, `docs-sync.md:各ゲート節`, `init-docs.md:21-26`

## デプロイ方法

アクティブコマンドは `~/.claude/commands/` へのシンボリックリンクでグローバルデプロイされる。

```bash
# シンボリックリンク例
ln -s <repo_root>/task.md ~/.claude/commands/task.md
ln -s <repo_root>/templates ~/.claude/commands/templates
```

根拠: `~/.claude/commands/` 内の各ファイルがリポジトリルート直下へのシンボリックリンクとして実在することを確認済み

## WIP コミットマーカー（task フロー）

task フローでは WIP コミットで進捗を管理する:
- `[/task:wip] #<issue番号> <実装内容の要約>`
  - 根拠: `task.md:180`
- Phase 2（ドラフト PR 作成）のガードは `[/task:wip]` プレフィックスの存在確認で行う
  - 根拠: `task.md:189-192`

## 実行コマンド（repo.profile.json 観点）

- `repo.profile.json.commands` は空（このリポジトリ自体に run/build/test コマンドは存在しない）
  - 根拠: `docs/.ai/repo.profile.json`
- 外部 CLI として `git`, `gh` をコマンド仕様内で使用する
  - 根拠: `task.md:105-109`, `patch.md:58-62`
