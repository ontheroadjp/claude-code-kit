# /task

このファイルは `commands/work.md` から Read されることを前提とした、docs 変更を伴う実装専用のワークフローです。ゲート確認・ルーティング判定・stash 管理は work.md が担います。

- 想像・憶測は一切禁止
- すべての判断は docs/.ai/repo.profile.json および docs の記述に基づく
- **docs/* の変更は行わない** — ドキュメント同期は /docs-sync が担う
- 全ての作業は issue と紐づく（issue がない場合は自動生成する）
- ワークフローは 3 フェーズで構成される

```
Phase 1: 実装（コード変更を完結させる）
Phase 2: ドラフト PR 作成 → /docs-sync 自動実行
Phase 3: 最終報告
```

フェーズをまたいで遡ることはない（フェーズ内の Step を遡ることは許容）。

---

## github 操作の注意点
- gh コマンドでは GraphQL 関連エラーが発生することがある
- gh api（REST PATCH）で PR 本文を直接更新する
- `gh pr create/edit` の本文は `\n` では改行されない
- 改行が必要な場合は `--body-file -` で標準入力を使用する
- Issue の内容取得は `--json` オプションで JSON 形式で取得する

---

## ワークフロー

### Phase 1: 実装

#### Step 0: issue の確認・自動生成（必須）

- /patch からのエスカレーションの場合:
    - patch.md 側で issue が作成済みのため、その issue 番号を引き継ぐ
    - `gh issue view <番号> --json title,body` で内容を確認する
    - Step 1 はスキップして Step 2 へ進む

- ユーザーが issue 番号を伝えた場合:
    - `gh issue view <番号> --json title,body` で内容を確認する
    - 以降その issue を作業の起点とする

- issue 番号が伝えられていない場合:
    - `~/.config/claude-code-kit/templates/issue.md` をもとに issue のドラフトを作成してユーザーに提示する
    - **issue のタイトル・本文は英語で記述する**
    - ユーザーの OK が出たら `gh issue create` で作成する
    - 作成した issue 番号を以降の起点とする

以降、全てのコミットメッセージに `#<issue番号>` を含める。

#### Step 1: 現状調査の引き継ぎと補完

- work.md の現状調査結果を引き継ぐ
- Step 2（プラン策定）に必要な情報が不足している場合のみ、差分を調査・補完する
- 未確認事項が残る場合はユーザーに報告し、確定するまで Step 2 に進まない

※ 事実が確定できない場合、ユーザーに理由を報告し、提案を提示して判断を仰ぐ

#### Step 2: プラン策定（必須・スキップ不可）
以下を含む作業プランを確定する:

- 完了条件
- 変更前 / 変更後の状態（Before / After）
- 変更対象（最小単位）
- 想定される影響とリスク
- 検証方法（成功条件）
- ロールバック方針
- タスクリスト（以下を必ず含む）
    - 作業ブランチの作成（feat/change/fix/test/chore-<slug>）
        - /patch からのエスカレーションの場合はブランチ再利用（新規作成しない）
    - 実行手順（順序付き）
    - テストケースの作成/更新
    - テストの実行

※ Step 3 実行前に調査結果・作業プランをユーザーに提示し、明確な許可を得ること（必須）

ユーザーから OK が出た場合:
    - 調査結果・作業プランを対象 issue の本文に追記する
    - Step 3 へ進む

ユーザーから質問や変更があった場合:
    - ユーザーの質問・変更に対応する

#### Step 3: 実行
3.1 作業プランに従って実装を行う
3.2 実装完了後:
    - 作業内容をユーザーに報告
    - ユーザーに実機テストおよびコードレビューを促して待機
    - ユーザーから追加指示が出た場合:
        - Step 2（必要に応じて Step 1）へ戻る
        - ゲートは通過済みの前提で作業を続ける
    - ユーザーから OK が出た場合:
        - `~/.config/claude-code-kit/partials/git-commit.md` を Read し、その手順に従ってコミットする
            - パラメータ: `issue_number=<Step 0 で確定した issue 番号>`, `allowed_types=[feat, fix, refactor, chore, style, test, docs]`
        - 作業内容を対象 issue のコメントとして投稿する
        - ユーザー確認なしに即座に Phase 2 へ進む

---

### Phase 2: ドラフト PR 作成

ガード:
- main ブランチ以外にいること
- `git log main..HEAD --oneline` の出力が 1 件以上あること（実装コミットが存在すること）
- ワークスペースがクリーンであること
    - クリーンでない場合: `git stash push -m "task-phase2: auto stash"` で退避してから進む

#### Step 1. ドラフト PR 作成

- `~/.config/claude-code-kit/templates/pr.md` をもとに PR 本文を作成する
- **PR のタイトル・本文は英語で記述する**
- PR はドラフトとして作成する。本文は `--body-file -` で標準入力から渡す:
    ```bash
    gh pr create --draft --title "#<issue number> <PR title in English>" --body-file - <<'EOF'
    [~/.config/claude-code-kit/templates/pr.md の内容を実際の値で埋めたものを展開]
    EOF
    ```
- 作成完了後、ユーザーに確認する:
    **「追加の変更はありますか？」**
    - あり → Step 3 に戻って実装・コミットする（`git push` で PR に自動反映される）
    - なし → `/docs-sync` を自動実行する（docs 同期 → PR 公開まで完結させる）
- `/docs-sync` が HARD STOP した場合はそこで処理が止まり、ユーザーへ報告される
- `/docs-sync` 完了後、Phase 3 へ進む

---

### Phase 3: 最終報告

A. 実装したファイル（テストを除く）
B. 作成/更新したテスト
C. テストの実行結果
D. issue URL
E. PR URL（/docs-sync により公開済み）
