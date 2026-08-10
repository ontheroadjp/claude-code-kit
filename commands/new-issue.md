# /new-issue

漠然としたアイデアを 1 件または複数件の整形された GitHub issue に変換する、`/work` の前段に置く任意のエントリポイントです。実装は行いません（実装はユーザーが作成された issue 番号に対して別途 `/work` を呼びます）。

- `/work` と独立した任意の pre-step です。`/work` 単独利用は従来通りサポートされます
- 起点情報は全てユーザーから引き出します。AI による補完・推測は禁止
- 作成する issue は `${TEMPLATES_DIR}/issue.md` の構成に従います
- **issue のタイトル・本文は英語で記述する**
- スコープが 1 件の coherent unit を超えると判断した場合、明示的な分割理由付きで複数 issue に分けて作成します
- 複数 issue に分割する際、GitHub の task list 機能を使って進捗を自動追跡する親（tracking）issue も選択的に作成できます（Step 3 参照）

template 参照時の `TEMPLATES_DIR` は実行 agent に応じて決定する:
- Claude Code: `~/.claude/templates`
- Codex CLI: `~/.codex/templates`

---

## ワークフロー

### Step 0: 前提確認

- 現在ブランチが `main` であることを確認する（実装は伴わないため、ブランチ切り替え・ゲートは不要）
- `gh auth status` でログイン済みであることを確認する

### Step 1: アイデア捕捉

ユーザーに以下を尋ねる:

- 解決したい問題・実現したいことは何か（1〜2 文で）
- どのような場面・利用シーンを想定しているか

不明瞭な点があれば短く追加質問する。**推測で埋めない**。

### Step 2: 明確化

Step 1 で得た情報をもとに、以下のうち未確定の項目を 1 件ずつユーザーに確認する:

- 背景（なぜ今これが必要か。既存の不便・直近の出来事・上流の意思決定など）
- 現状の挙動（既存機能・既存コマンド・既存ファイルへの言及があれば、現状を簡潔に把握）
- 制約（変えてはいけないもの、互換性、運用上の前提）
- 完了条件のシグナル（何が起きれば「完了」と判定できるか）

回答を整理した時点で**ユーザーに整理結果を提示し、認識ズレがないか確認**する。

### Step 3: スコープ判定（ユーザー選択必須）

スコープを分割するかどうかは **ユーザーが決定する**。以下の 4 つの選択肢を提示し、選択を仰ぐ:

1. **issue を分割しない** — 1 件のシンプルな issue として作成する
2. **1 つの issue で Phase 分割** — 1 件に保ち、本文 Scope に Phase 1 / Phase 2 / ... を明示する
3. **親子issue として分割（N 件）** — 1 件の親（tracking）issue と、それに紐づく N 件の子issue を作成する。親issue本文に GitHub の task list 記法（`- [ ] #<子issue番号>`）で子issue一覧を列挙し、子issue が close された時に親issue側のチェックが GitHub のネイティブ機能で自動的にオンになる（分割案を提示する）
4. **単体で分割（N 件）** — 親子関係を持たない、独立した関心ごとの issue を N 件作成する（分割案を提示する）

**Claude の推奨: [1 / 2 / 3 / 4] — [Step 1/2 の事実に基づく理由]**

**ルール:**
- 推奨の根拠は Step 1/2 で得た**事実のみ**を引用する（推測・補完禁止）
- ユーザーが選択するまで Step 4 へ進まない
- ユーザーが追加情報を求めた場合は応じる。Step 2 で漏れていた論点が出た場合は Step 2 に戻って明確化する

**選択結果と Step 4 の対応:**
- [1] を選択 → 1 件のドラフト（Phase 構造なし）
- [2] を選択 → 1 件のドラフト（本文 Scope に Phase 構造を含める）
- [3] を選択 → 親 1 件 + 子 N 件 = 計 N+1 件のドラフト（Step 4「親子issue化」の構成に従う）
- [4] を選択 → N 件のドラフト（各 issue を独立して作成）

### Step 4: ドラフト作成

作成対象の各 issue について、`${TEMPLATES_DIR}/issue.md` の構成に従ってドラフトを作成する:

- タイトル: 英語、簡潔に what + 主目的を表現する
- 本文の各セクション（Overview / Background / Scope (initial estimate) / Done Criteria）を埋める
- 埋められない箇所は推測せず、ユーザーに確認する
- 「Changes Already Made in /patch」「Additional Scope」セクションは `/new-issue` では使用しない（テンプレートのコメント通り削除する）

#### 親子issue化（Step 3 で [3] を選択した場合）

- 子issue（N 件）は通常のドラフトのまま作成する（内容の変更なし）
- 親issue 1 件は `${TEMPLATES_DIR}/issue.md` の Scope (initial estimate) セクションを子issue一覧の説明に置き換え、GitHub の task list 記法（`- [ ] #<子issue番号>`）で子issue一覧を列挙する
    - GitHub は task list 内で参照した issue が close されると、該当行のチェックボックスを自動でオンにするネイティブ機能を持つため、これを利用する。子issue側の本文には手動でチェックを入れる手順を書かない
    - 子issue番号は Step 5 で子issueを先に作成した後に確定するため、親issueのドラフトはこの時点では番号欄をプレースホルダのまま提示してよい

全件のドラフトを**まとめてユーザーに提示**し、OK を取る。修正があれば対応する。

#### ラベル選定

ドラフト OK 後、各 issue に付与するラベルを決定する:

1. `gh label list` で既存ラベルを取得する
2. issue の内容（タイトル・Overview・Scope）に基づいて最も適切なラベルを選定し、**ユーザー確認なしに採用する**

**適切なラベルが存在しない場合:**
- 「既存ラベルに適切なものが見つかりませんでした」とユーザーに報告する
- 推奨する新規ラベルを以下の形式で提案する:
  - name: `<ラベル名>`
  - description: `<説明>`
  - color: `<16進カラーコード（例: #0075ca）>`
- ユーザーが承認した場合: `gh label create --name "<name>" --description "<description>" --color "<color>"` で作成し、そのラベルを採用する
- ユーザーが拒否した場合: ラベルなしで issue を作成する

### Step 5: issue 作成

ユーザー OK 取得後、各 issue を作成する。ラベルが決定している場合は `--label` を付与する:

```bash
# ラベルあり
gh issue create --title "<English title>" --label "<label>" --body-file - <<'EOF'
<English body>
EOF

# ラベルなし
gh issue create --title "<English title>" --body-file - <<'EOF'
<English body>
EOF
```

各作成で得られた issue 番号と URL を保持する。

**親子issue化した場合（Step 3 で [3] を選択した場合）の作成順序（必須）:**
1. 子issue（N 件）を先に全件作成し、番号を確定する
2. 確定した子issue番号を親issueドラフトの task list に埋め込んでから親issueを作成する
3. 親issue作成後、各子issueに以下でコメントを投稿し、双方向に参照できるようにする（子issue本文自体は編集しない）:
    ```bash
    gh issue comment <子issue番号> --body "Parent tracking issue: #<親issue番号>"
    ```

### Step 6: 引き継ぎ案内

作成した issue を一覧で報告する:

- 件数（1 件 or 複数件）
- 各 issue の番号・タイトル・URL
- 親子issue化した場合は、親issueの番号・URLと、close時に子issueのチェックが自動連動する旨を明記する
- 次のステップとして「実装に進む場合は `/work` を呼んでください。issue 番号を渡すと該当 issue を起点に作業を開始できます」と案内する
- **`/work` を自動呼び出ししない**。ユーザー任意で次の操作を選択させる

---

## スコープ外

- 実装・コード変更・ブランチ作成
- PR 作成・ドキュメント同期
- 既存 issue の編集・クローズ

これらは `/work` および委譲先のコマンドが担う。`/new-issue` は issue 作成のみで完結する。
