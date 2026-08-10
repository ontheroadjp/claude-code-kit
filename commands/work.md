# /work

全ての作業のエントリポイントです。ゲート確認・ワークスペース管理・ルーティング判定を行い、report issue は `commands/report-review.md`、auto-approve-candidate issue は `/triage-issues-for-auto-approve` の実行を案内して終了し、それ以外は `commands/task.md` または `commands/patch.md` を Read して委譲します。

---

## 実行前提ゲート（必須）

### G-0: main ブランチへの切り替え

まず `git rev-parse --show-toplevel` を実行し、その結果が `.claude/worktrees/` を含むかを判定する。含む場合（`EnterWorktree` が作成した worktree 内で実行されている場合。例: `/work-multi`）は `main` が主 worktree で既にチェックアウトされているため `git checkout main` を実行せずスキップし、G-1 へ進む。含まない場合は `git checkout main` を実行し、main ブランチに切り替える（通常の非 worktree checkout ではこの分岐は常に false になるため、以下は従来と同一の動作である）。

（issue #261 で追記: 以前はここで前回の `/work` 呼び出しの `session-approved` を空文字列で防御的にクリアしていたが、廃止した。`hooks/auto-approve-readonly.sh` の Write ハンドラは「ファイルが absent の場合のみ」無条件承認する初回書き込みブランチに入るため、この空書き込みは `hooks/cleanup-session.sh`（Stop hook）が正常に削除済みの absent 状態を「exists-empty」状態に変換してしまい、直後の `task.md`/`patch.md` Step 2 の実承認内容の書き込みが既存内容（空）との差分比較で毎回確実にスコープ拡大としてブロックされる原因になっていた。Stop hook が正常に動作していれば `session-approved` は既に absent であり、G-0 が何もしなくても Step 2 の書き込みが自然に初回書き込みとして承認される。Stop hook が削除に失敗していた場合（真にイレギュラーなケース）は、Step 2 の書き込みが既存のスコープ拡大チェックにそのまま委ねられ、通常の確認プロンプトにフォールスルーする。`rm -f` への回帰は検討したが不採用とした: commit 87ce937（fix #250）が `session-approved` を `rm -f` の自動承認対象から明示的に除外しており（`is_rm_protected_path`）、これはエージェントが確認なしにスコープガードのベースラインをリセットできる抜け穴を塞ぐためのもの。G-0 を `rm -f` に戻すと、この抜け穴を「レアケースの救済」としてではなく「通常フローで毎回」再開放することになる。）

（issue #296 で追記: worktree パスガードを追加した。`EnterWorktree` は常に `.claude/worktrees/<name>` 配下に worktree を作成する固定仕様のため（ツール自身の仕様）、この配下にいるかどうかは `git checkout main` を試行する前に確実に判定できる。実機検証の結果、worktree 内で `git checkout main` を実行すると `main` は主 worktree で既にチェックアウトされているため `fatal: 'main' is already used by worktree at '<主worktreeのパス>'` で必ず失敗することを確認した。この失敗を実行してからエラー文言を解釈するのではなく、事前のパスチェックで確実に回避する設計とした。通常の非 worktree checkout では `git checkout main` は workspace が clean であれば元のブランチとの分岐状況に関わらず常に成功することも実機で確認済みであり、このガードは非 worktree の場合の挙動に一切影響しない。）

### G-1: docs/.ai/repo.profile.json の存在確認
- 存在しない場合: /init-docs の実行を促して終了する
- 存在する場合: 内容を Read し、以降の調査フェーズの起点として活用する

### G-2: main ブランチの場合、ワークスペースの確認

`git status --porcelain` を実行する。

差分がある場合、以下の選択肢をユーザーに提示する:

**未コミットの変更が検出されました。どう扱いますか？**
1. **今回の作業に乗せる** — 現在の変更をこの作業の一部として扱う
2. **stash して退避** — 変更を一時退避し、クリーンな状態で新規作業を開始する
3. **中断** — 何もせず終了する

- [1] を選択した場合:
    - 変更はそのまま保持する（stash しない）
    - ルーティング判定へ進む
- [2] を選択した場合:
    - `git stash push -m "work-gate: auto stash"` で退避する
    - 「未コミット変更を stash に退避しました。作業完了後に復元します」と通知する
    - ルーティング判定へ進む
- [3] を選択した場合:
    - 処理を終了する

差分がない場合はそのままルーティング判定へ進む。

---

## 開始判定とルーティング

### ブランチ分類

以降の (A)/(B) 判定は、現在のブランチ名が `main` かどうかの単純比較ではなく、`/task`・`/patch` が作業ブランチに使う命名規則のいずれかに一致するかで行う:

- `/task`（`task.md`）の命名規則: `feat/`, `change/`, `fix/`, `test/`, `chore-`
- `/patch`（`patch.md`）の命名規則: `patch/`

いずれかの prefix に一致する場合 → (B) 再開・エスカレーション
一致しない場合（`main` 自身、および `EnterWorktree` が作成する `worktree-` prefix のブランチを含む、上記いずれにも一致しない全てのブランチ）→ (A) 新規作業

（issue #296 で追記: 以前は「現在ブランチが main か」の単純比較だったが、worktree 内で G-0 の `git checkout main` がスキップされるケース（ブランチ名が `worktree-<name>`）を正しく (A) 新規作業として扱うために、判定基準を「`/task`・`/patch` が実際に作成する命名規則に一致するか」へ変更した。通常の非 worktree checkout では、`git checkout main` が成功した時点でブランチは必ず文字通り `main` になり、これはどの命名規則にも一致しないため (A) に分類される。checkout が失敗して非 main ブランチのまま残るのは、既存の `/task`・`/patch` フローが作成した命名規則付きブランチ上で作業中だったケースにほぼ限られるため、既存の (B) 判定結果は変わらない。）

### 現状調査（共通）

(A)・(B) いずれの分岐でも、ルーティング判定または開始フェーズ報告の前に必ず以下を調査・整理する:

- `docs/.ai/repo.profile.json`（G-1 で Read 済み）の `primary_docs` が存在する場合、まず `primary_docs.investigation` を Read して変更対象ファイルの候補を絞り込む。候補ファイルに対応する L3 per-file doc（`docs/L3_implementation/<path>.md`）が存在する場合は、まずその doc を Read し、関連セクションの `根拠: <file>:<line-range>` citation を確認したうえで、候補ファイル本体の Read は該当行範囲を `offset`/`limit` で指定した対象読みに絞る。L3 doc が存在しない、または対象箇所を特定できない場合は候補ファイルを直接 Read して現在の状態を確認する。同一セッション内で既に読んだ範囲を対象理由なく再度 Read しない。ドキュメントだけでは対象ファイルを特定できない場合のみ Glob/Grep を実行する
- `primary_docs` が存在しない場合は `active_commands`・`doc_roots`・`deploy` を起点に対象ファイルを絞り込む
- 変更対象となるファイル・関数・設定を特定する
- 現在の振る舞いを把握する
- 影響範囲（ファイル・テスト・設定）を列挙する
- 不明点があれば未確認事項として明示する

この調査結果は task.md または patch.md の実装フェーズに引き継がれる。
G-1 で Read した `docs/.ai/repo.profile.json` および現状調査で Read した `docs/L3_implementation/specification_summary.md` はコンテキスト内に保持されているため、task.md / patch.md で再度 Read しない。

### (A) 上記のブランチ分類が新規作業に該当する場合

ユーザーに作業の目的を尋ねる。

#### issue label の事前ルーティング

ユーザーが issue 番号を明示している場合、現状調査より先に以下で label を取得する:

```bash
gh issue view <issue番号> --json labels --jq '.labels[].name'
```

- label に `report` が完全一致で含まれる場合:
    - `commands/report-review.md` を Read し、その内容に従う
    - `/task`・`/patch` へのルーティング、ブランチ作成、実装は行わない
    - `/report-review` の完了後に `/work` も終了する
- label に `report` は含まれないが `auto-approve-candidate` が完全一致で含まれる場合:
    - `/task`・`/patch` へのルーティング、ブランチ作成、実装は行わない
    - 「この issue には auto-approve-candidate label が付いています。実装前に `/triage-issues-for-auto-approve` を実行してハザード審査を受けてください」と報告し、`/work` を終了する
    - このチェックは `/triage-issues-for-auto-approve` で承認され `triage-approved` label に付け替えられた issue には適用されない（label が既に外れているため自然に該当しなくなる）
- いずれの label にも該当しない場合:
    - 既存どおり現状調査と2段階ルーティングへ進む
- issue の取得に失敗した場合:
    - エラーを報告して終了し、推測でルーティングしない

#### 現状調査

上記「現状調査（共通）」を実行する（ルーティング判定の前に必ず行う）。

issue label の事前ルーティングに該当しなかった場合、以下の2段階でルーティングを判定する:

**判定基準:**

**【第1段階】issue 起点か？**
- ユーザーが「issue #N を対応する」「issue がある」など issue を明示している場合 → **`/task`**
- issue が存在しない場合 → 第2段階へ

**【第2段階】docs 変更が必要か？**
「この変更の結果として、docs/* に対して追加・変更・削除のいずれかが必要になるか？」

**【参考: 変わる可能性が高い変更】**
- ディレクトリ構造・API・公開関数のシグネチャや振る舞い
- 公開機能・設定項目の追加・削除・変更
- 実行コマンド・起動方法・DB スキーマ・CI 定義
- 本番依存（dependencies）の追加・削除

**【参考: 変わらない可能性が高い変更】**
- typo・コメント・ログ文言の修正
- 外部インターフェースを変えないリファクタリング
- テストの追加・修正（テスト戦略の変更を伴わない）
- devDependencies の変更

→ **issue 起点、または docs 変更が必要な場合:**
`commands/task.md` を Read し、その内容に従って作業を進める。
- G-2 は通過済みとして扱う（stash 状態も引き継ぐ）
- task.md の「Phase 1 Step 0」から開始する

→ **issue なし かつ docs 変更が不要な場合:**
`commands/patch.md` を Read し、その内容に従って作業を進める。
- G-2 は通過済みとして扱う（stash 状態も引き継ぐ）
- patch.md の「Phase 1 Step 1」から開始する

### (B) 上記のブランチ分類が再開・エスカレーションに該当する場合

ルーティング判定はスキップする（既に作業として進行中のため）。

1. `git status --porcelain` が空でない（未コミット変更がある）場合:
    - `commands/task.md` を Read し、Phase 1 から継続する
2. `git log main..HEAD --oneline` の出力が 1 件以上あり、ワークスペースがクリーンな場合:
    - issue 番号は `gh pr view --json body` のドラフト PR 本文、またはコミットメッセージの `(#N)` パターンから取得する
    - `commands/task.md` を Read し、Phase 1 Step 2 から開始する（session-approved 再作成のため）。session-approved 作成後は Step 3 をスキップし、直接 Phase 2 へ進む
3. それ以外:
    - `commands/task.md` を Read し、Phase 1 から開始する

#### 現状調査

上記「現状調査（共通）」を実行する（開始フェーズ報告の前に必ず行う）。

判定後、開始フェーズとその理由を報告し、ユーザーの許可を得てから作業を開始する。

---

## stash の復元

委譲先（task.md または patch.md）の作業が完全に完了した後、G-2 で [2] を選択して stash した場合のみ以下を実行する:

- `git stash pop` で変更を復元する
- コンフリクトが発生した場合:
    - 「stash の復元でコンフリクトが発生しました。手動で解決してください」とユーザーに通知する
    - 解決方法の指示をユーザーに仰ぎ、指示に従う
