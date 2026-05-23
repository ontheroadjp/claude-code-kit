# Operation Model

## コマンド使い分けの判定ロジック

ユーザーは常に `/task` を呼ぶ。`task.md` 内部でルーティング判定を行い、patch フローまたは task フローを実行する。

**判定基準（単一質問）:**
「この変更の結果として、`docs/*` に対して追加・変更・削除のいずれかが必要になるか？」

- → 変わらない場合: patch フロー（branch + commit、issue/PR なし）
- → 変わる場合: task フロー（issue → 実装 → ドラフト PR → /docs-sync）

根拠: `commands/task.md`（ルーティング判定・patch フロー節）

## ワークフロー概要

### 軽微な修正（patch フロー）
```
/task 呼び出し
→ ルーティング判定（docs 変更不要）
→ patch.md のワークフローを実行
→ branch 作成（patch/<slug>）
→ 変更・コミット
→ ユーザーが main へ ff-merge
```
根拠: `commands/task.md`（patch フロー節）, `commands/patch.md`

### ドキュメントを伴う実装（task フロー）
```
/task 呼び出し
→ ルーティング判定（docs 変更あり）
→ issue 確認/自動生成
→ Step1: 現状調査
→ Step2: プラン策定（ユーザー許可必須）
→ Step3: 実装・コミット（Conventional Commits）
→ Phase 2: ドラフト PR 作成（commands/templates/pr.md 使用）
→ /docs-sync 自動実行（docs・README.md 更新 → PR 公開）
```
根拠: `commands/task.md`（Phase 1–3）

### ドキュメント同期（/docs-sync）
```
/docs-sync 呼び出し
→ git diff --name-only で変更ファイル確定
→ HARD STOP 判定（全体再構築が必要か）
→ 対象 docs および README.md を最小更新
→ ドラフト PR を公開（ready）
```
根拠: `commands/docs-sync.md`（各フェーズ）

### ドキュメント全体再構築（/init-docs）
再実行トリガー:
- `/docs-sync` が HARD STOP を検知した場合
- docs が現状を説明できなくなった場合
- 新規レイヤ導入・エントリポイント変更の疑いがある場合

根拠: `commands/init-docs.md:9-19`

## ゲート設計

| コマンド | G-1 | G-2 | G-3 | G-4 |
|----------|-----|-----|-----|-----|
| task.md | repo.profile.json 必須 | main かつクリーン（stash） | - | - |
| patch.md | repo.profile.json 必須 | main ブランチにいること | クリーン（stash） | - |
| docs-sync.md | repo.profile.json 必須 | docs/ 必須 | main 以外のブランチ | PR 存在確認 |
| init-docs.md | .git/ 必須 | - | - | - |

根拠: `commands/task.md`（G-1/G-2節）, `commands/patch.md`（G-1–G-3節）, `commands/docs-sync.md`（G-1–G-4節）, `commands/init-docs.md:21-26`

## デプロイ方法

**原則: `~/.claude/` 配下には実体ファイルを置かない。全て本リポジトリへのシンボリックリンクとする。**
このリポジトリが single source of truth であり、`~/.claude/` はその参照点に過ぎない。ファイルを直接 `~/.claude/` に置いた場合、リポジトリとの乖離が発生し管理が破綻する。

全成果物はシンボリックリンクでグローバルデプロイされる:

```bash
# commands
ln -s <repo>/commands/task.md       ~/.claude/commands/task.md
ln -s <repo>/commands/patch.md      ~/.claude/commands/patch.md
ln -s <repo>/commands/docs-sync.md  ~/.claude/commands/docs-sync.md
ln -s <repo>/commands/init-docs.md  ~/.claude/commands/init-docs.md
ln -s <repo>/commands/templates     ~/.claude/commands/templates

# CLAUDE.md（全セッション自動ロード）
ln -s <repo>/CLAUDE.md              ~/.claude/CLAUDE.md

# hooks
ln -s <repo>/hooks/log-token-usage.sh ~/.claude/hooks/log-token-usage.sh
```

根拠: `README.md:30-75`（Installation セクション）

## コミット形式（task フロー）

task フローのコミットは Conventional Commits 形式を使用する:
- `<type>(#<issue番号>): <short description in English>`
  - 例: `feat(#23): implement user auth endpoint`
  - 根拠: `commands/task.md`（Step 3 コミット節）
- Phase 2（ドラフト PR 作成）のガードは `git log main..HEAD --oneline` の出力が 1 件以上あることで行う
  - 根拠: `commands/task.md`（Phase 2 ガード節）

## 実行コマンド（repo.profile.json 観点）

- `repo.profile.json.commands` は空（このリポジトリ自体に run/build/test コマンドは存在しない）
  - 根拠: `docs/.ai/repo.profile.json`
- 外部 CLI として `git`, `gh`, `jq` をコマンド仕様・hooks 内で使用する
  - 根拠: `commands/task.md`（github 操作の注意点節）, `hooks/log-token-usage.sh:5`

## token 使用量ログ

セッション終了時に Stop hook が自動実行され、`~/.claude/token-usage.log` に以下の形式で追記される:
```
[timestamp] session=<id>  input=N  output=N  cache_read=N  cache_create=N  total=N
```
- `total` = input + output + cache_create（cache_read は既存キャッシュの読み取りで課金対象外）
- 根拠: `hooks/log-token-usage.sh`, `~/.claude/settings.json:hooks.Stop`
