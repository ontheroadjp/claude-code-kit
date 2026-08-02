# /report-review

`report` label が付いた GitHub issue を、実装やファイル変更を行わずに評価する read-only workflow です。通常は `/work #N` から委譲されます。

## 境界

- リポジトリと GitHub の状態は読み取り専用で扱う
- ファイルの作成・編集・削除は禁止
- Git の共有状態・履歴・working tree の変更は禁止
- GitHub issue / PR の変更は禁止
- branch 作成、commit、push、PR 作成、issue へのコメント投稿は行わない
- 評価結果は GitHub へ投稿せず、標準出力にだけ提示する

上記の境界に反する操作が必要になった場合は実行せず、提案として出力する。`/task`、`/patch`、`/docs-sync`、`/git-pr` へは委譲しない。

---

## ワークフロー

### Step 0: 入力と認証の確認

- issue 番号が指定されていない場合は、番号を尋ねて待機する
- `gh auth status` で GitHub CLI が利用可能であることを確認する
- 認証されていない場合は、`gh` にログインしてから再実行するよう報告して終了する

### Step 1: report issue の取得と検証

以下で対象 issue を取得する:

```bash
gh issue view <番号> --json number,title,body,labels,url,state
```

- 取得に失敗した場合はエラーを報告して終了する
- label の name が `report` と完全一致することを確認する
- `report` label がない場合は、対象外であることを報告して終了する。label の追加や `/task` への切り替えは行わない
- title、body、state、labels、URL を評価の起点として保持する

### Step 2: 評価に必要な根拠の収集

issue の主張と提案を項目に分け、各項目の評価に必要な範囲だけを読み取る。

1. `docs/.ai/repo.profile.json` が存在する場合は Read し、リポジトリ構成と調査起点を確認する
2. `primary_docs.investigation` が存在する場合は Read する
3. report 本文が言及する command、source、test、configuration、docs を直接 Read する
4. report だけでは対象を特定できない場合に限り、`rg` または `rg --files` で候補を絞り、候補ファイルを直接 Read する
5. 必要に応じて read-only な Git/GitHub 情報を確認する

根拠として確認していない内容は事実として扱わない。issue の記述とリポジトリの事実が異なる場合は、両者を明確に分離する。

### Step 3: 評価

以下を区別して整理する:

- **Facts**: issue とリポジトリから直接確認できた事実
- **Assessment**: report の主張ごとの妥当性、重要度、現在の設計との整合性
- **Opinions**: 根拠から導いた見解。事実や report 原文と混同しない
- **Proposals**: 実施候補。優先度、理由、期待効果を含める
- **Risks and Unknowns**: 未確認事項、判断材料不足、提案を実施する場合のリスク

提案は評価に留め、実装計画の承認取得や変更作業には進まない。

### Step 4: 標準出力への提示

以下の形式で出力する:

```text
## Report Review #<number>: <title>

### Summary
<report の目的と総合評価>

### Facts
- <確認した事実。可能な場合は file:line または issue URL を付ける>

### Assessment
- <主張ごとの評価と根拠>

### Opinions
- <事実と分離した見解>

### Proposals
1. [priority: high|medium|low] <提案>
   - Rationale: <理由>
   - Expected impact: <期待効果>

### Risks and Unknowns
- <リスクまたは未確認事項。なければ「なし」>
```

最後に「read-only review のため、ファイルおよび GitHub の変更は行っていません」と明記して終了する。
