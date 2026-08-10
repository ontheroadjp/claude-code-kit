# /task specification

## 目的・役割

`commands/task.md` は `commands/work.md` から委譲される、**docs 変更を伴う実装専用のワークフロー**である。issue の確認・自動生成、実装、L3 per-file doc 作成、ドラフト PR 作成、`/docs-sync` 自動実行を担う。

ゲート確認・ルーティング判定・stash 管理は work.md が担うため、task.md 内では重複して行わない。

根拠: `commands/task.md:1-15`

## 動作の概要

3 フェーズで構成される:

```
Phase 1: 実装（issue 確認/自動生成 → 調査補完 → プラン策定・承認 → 実装 → L3 doc 作成 → commit）
Phase 2: PR 本文の準備 → /docs-sync 自動実行 → /git-pr 自動実行
Phase 3: 最終報告
```

フェーズをまたいで遡ることはない（フェーズ内の Step を遡ることは許容）。

根拠: `commands/task.md:11-17`

## 主要なフロー

### Phase 1

#### Step 0: issue の確認

以下の 3 ケースを処理する:

1. `/patch` からのエスカレーション: patch 側で作成済みの issue 番号を引き継ぐ
2. ユーザーが issue 番号を指定済み: `gh issue view` で内容確認し以降の起点とする
3. issue がない: Step 2 のプラン承認後に自動作成する（`commands/new-issue.md` の Step 4-5 のみ実行）

ケース 3 で自動作成する場合、確定済みプランの内容（完了条件・背景・変更対象・検証方法）を issue テンプレートに英語で埋める。ユーザー確認はスキップ（プラン承認で確定済みのため）。

根拠: `commands/task.md:32-48`

#### Step 1: 現状調査の引き継ぎと補完

work.md の調査結果を引き継ぎ、プラン策定に必要な情報が不足している場合のみ補完する。

**変更対象ファイルが確定したら、`docs/L3_implementation/<対象ファイルパス>.md` が存在する場合は必ず Read する。** 設計意図・現状仕様を把握してから Step 2 へ進む。存在しない場合はスキップ（Step 3.2 で新規作成する）。

根拠: `commands/task.md:50-66`

#### Step 2: プラン策定（必須・スキップ不可）

以下を含む作業プランを確定し、ユーザーの明確な許可を得る:

- 完了条件、Before/After、変更対象（最小単位）、影響とリスク、検証方法、ロールバック方針
- 利用ツール（`tool:git_write` / `tool:gh_issue_write:<N>` / `tool:gh_pr_write:<N>`。N は対象 issue 番号 — issue #297 でカテゴリを対象番号にスコープ化。`create` verb は N に関わらず常に承認されるため `tool:gh_pr_write:<N>` の N には形式的にこの issue 番号を流用する）。**`tool:gh_issue_write:<N>` は `/task` フローでは常に列挙する** — Step 3.2 の完了コメント投稿が issue の新旧を問わず必ず発生するため、条件付き判定の対象にしない（issue #250）
- 新規作成・編集ファイルの絶対パス。プラン本文で言及した実装ファイル・テストファイルを漏れなく転記する
- Step 3.2 で作成・更新する L3 per-file doc の絶対パス（`docs/L3_implementation/<source-path>.md`）

ユーザーから OK が出た後（issue #297: session-approved 書き込みに N が必要になったため、旧来の「書き込み→未作成なら作成」の順序を反転した）:
1. issue が未作成の場合は new-issue.md Step 4-5 で先に自動作成し、確定した issue 番号を N とする。この `gh issue create` 呼び出し自体は session-approved がまだ存在しないため通常の確認プロンプトに従う（1 回限りのトレードオフ）
2. issue が作成済みの場合は Step 0 で確定した番号を N とする
3. `$CLAUDE_CODE_SESSION_ID`（Codex は `$CODEX_THREAD_ID` のハッシュ）から自セッションの `session-approved` パスを直接導出し、ツールカテゴリ（`tool:gh_issue_write:<N>` 等）・実装ファイル・L3 doc パスを一括書き込みする（1 度だけ）
4. issue が元から作成済みだった場合のみ、調査結果・作業プランを issue 本文に追記する（今回新規作成した場合は Step 1 のドラフトが既に内容を含むため不要）

session-approved はこの Step で 1 度だけ書き込む。スコープ変更が必要な場合はこの Step に戻りユーザーの許可を得てから再書き込みする。

根拠: `commands/task.md:81-121`, issue #297

#### Step 3: 実行

3.1: 作業プランに従って実装する。

3.2: 実装完了後、ユーザーに報告して OK を得た後:

1. **L3 per-file doc の作成/更新**: 変更した各ソースファイルに対して `docs/L3_implementation/<path>.md` を作成または更新する。内容は**現時点のスナップショット**（changelog ではない）:
   - 目的・役割、動作概要、重要な設計判断とその理由、統合ポイント、注意事項
   - 過去の経緯は「なぜ現在の設計になっているか」を説明する場合にのみ含める
2. `/git-commit` を実行する（`issue_number=<N>`, `allowed_types=[feat, fix, refactor, chore, style, test, docs]`）
3. 作業内容を issue のコメントとして投稿する
4. ユーザー確認なしに即座に Phase 2 へ進む

根拠: `commands/task.md:107-128`

### Phase 2: PR 本文の準備

ガード: main 以外のブランチ、コミットが 1 件以上存在、ワークスペースがクリーンであること。

実行 agent に応じた `${TEMPLATES_DIR}/pr.md`（Claude Code は `~/.claude/templates`、Codex CLI は `~/.codex/templates`）を使って英語で PR 本文・タイトルを作成し、session temp directory に `pr-title.txt` と `pr-body.md` を書き出す。この時点では push も PR 作成も行わない。

ユーザーに「追加の変更はありますか？」と確認し、なければ `/docs-sync` を自動実行する。`/docs-sync` 完了後、ユーザー確認なしに即座に `/git-pr` を実行する（push → PR 作成まで完結）。

`/git-pr` による ready PR 作成が task フローのゴールである。作成後の review・merge は自動実行しない（人間、または `/review-resolve`・`/codex-review` を手動起動するユーザーが行う）。

根拠: `commands/task.md:139-163`, `commands/task.md:178-186`

## 設計上の決断

### "docs/* 変更禁止" の例外として L3 per-file doc を認める理由

従来の `docs/* の変更は行わない` ルールは、`/docs-sync` が git diff を事実として docs を更新するという分業を守るためのものである。

L3 per-file doc の更新を task.md が担う理由: `/docs-sync` は diff-driven であり、「なぜそうしたか」の設計意図を知らない。設計意図の記録は実装フロー（task.md）がコンテキストを持っているタイミングにしか書けない。この目的に限り docs/* への書き込みを許容する。

### プラン承認後に issue を自動作成する設計

issue を先に作ると「ラフなアイデア段階の issue」が残るリスクがある。task フローでは work.md 現状調査とプラン策定を経てから issue を作るため、issue の質が保証される。

ユーザーがプランを承認した時点で内容は確定しているため、issue 作成にユーザー確認を重ねる必要がない。

根拠: `commands/task.md:93-101`

### session-approved を Step 2 で 1 度だけ書き込む理由

session-approved への追記を hook が block するため、全スコープを確定させてから 1 度だけ書き込む設計になっている。スコープ変更が生じた場合は Step 2 に戻ることで、ユーザーの再承認を必須にする（無断スコープ拡大の防止）。

### session ID を環境変数から直接導出する理由（issue #210）

以前は Step 2 と Phase 2 Step 1 の両方で `${STATE_ROOT}/current-session-approved-path` という共有ポインタファイルを読んで `SESSION_ID`/`SESSION_TMP_DIR` を逆算していた。この共有ファイルはセッションでスコープされておらず、複数セッション同時実行時に他セッションの hook 呼び出しで上書きされ、誤ったパスを読み取る競合が発生していた。`$CLAUDE_CODE_SESSION_ID` が hook 側の解決結果と一致することを確認できたため、共有ファイルを経由せず直接導出する方式に変更した。詳細は `docs/L3_implementation/hooks/lib/session-id.sh.md` を参照。

## 統合ポイント

- 呼び出し元: `commands/work.md`（ルーティング判定後）、`commands/patch.md`（エスカレーション時）
- 呼び出すもの: `commands/new-issue.md`（Step 4-5 のみ）、`/git-commit`、`commands/docs-sync.md`、`commands/git-pr.md`
- PR テンプレート: `${TEMPLATES_DIR}/pr.md`（Phase 2 で temp ファイルに書き出す）
- issue テンプレート: `${TEMPLATES_DIR}/issue.md`
- template root: Claude Code は `~/.claude/templates`、Codex CLI は `~/.codex/templates`

## 注意事項

- ソースコードを修正する場合は修正前に言語対応の coding コマンド（`commands/coding-*.md`）を Read する。JSX/TSXではReact layerを追加し、`next` dependencyまたはNext.js configがあるprojectではさらにNext.js layerを追加する。
- `session-approved` に L3 per-file doc パスを含めないと hook がブロックするため、Step 2 で必ず含める
- task.md は docs-sync.md を自動実行し（Phase 2 Step 1）、完了後に git-pr.md を自動実行する。docs-sync の HARD STOP 時はユーザーへ報告して終了し、git-pr は実行しない

## 変更履歴（git log より自動生成）

- d4bd418 feat(#267): add /coding-sh command and enforce shellcheck across all shell scripts
- e4b3d18 fix: apply resolve-then-embed to task.md session tmp dir mkdir
- 87ce937 fix(#250): protect session-approved from auto-approved rm, tighten task.md Step 2 checklist
- db6d6c3 fix(#210): resolve session id from env instead of a shared pointer file
- 5a4ecc6 chore(#205): remove /pr-review; /work and /task now end at PR creation
- 27f1861 feat(#76): install templates for claude and codex
- 82717a1 feat(#167): add /git-pr command; refactor push and PR creation out of /task and /docs-sync
- 17c844b feat(#163): introduce L3 per-file docs and enforce reading them in task/patch flows
- 7f30935 feat(#161): defer issue creation to after plan approval in task flow
- 89d5fad feat(#157): move git-commit to commands/, add skill wrapper, update all callers to /git-commit
