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
3. `bash ~/.claude/hooks/lib/session-paths.sh session-approved`（Codex: `~/.codex/...`）で自セッションの `session-approved` パスを直接導出し、ツールカテゴリ（`tool:gh_issue_write:<N>` 等）・実装ファイル・L3 doc パスを一括書き込みする（1 度だけ）。以前はこの解決式を Bash スニペットとしてインライン展開していたが、worktree 隔離セッションで harness に拒否されるため `hooks/lib/session-paths.sh` 経由の単一プレーンな呼び出しに置き換えた（issue #316）
4. issue が元から作成済みだった場合のみ、調査結果・作業プランを issue 本文に追記する（今回新規作成した場合は Step 1 のドラフトが既に内容を含むため不要）

session-approved はこの Step で 1 度だけ書き込む。スコープ変更が必要な場合はこの Step に戻りユーザーの許可を得てから再書き込みする。

根拠: `commands/task.md:81-121`, issue #297

#### Step 3: 実行

3.1: 作業プランに従って実装する。作業ブランチを新規作成または既存ブランチへ切り替えた直後は、Claude Code でのみ Git が返す現在のブランチ名を `~/.claude/scripts/rename-thread.sh` に渡し、会話スレッド名を `/rename <作業ブランチ名>` と同じ結果になるよう更新する。Codex CLI ではこの操作をスキップする。ブランチ名を推測・手入力せず、更新失敗は Git の切替や実装を中断させない。

3.2: 実装完了後、ユーザーに報告して OK を得た後:

1. **L3 per-file doc の作成/更新**: 変更した各ソースファイルに対して `docs/L3_implementation/<path>.md` を作成または更新する。内容は**現時点のスナップショット**（changelog ではない）:
   - 目的・役割、動作概要、重要な設計判断とその理由、統合ポイント、注意事項
   - 過去の経緯は「なぜ現在の設計になっているか」を説明する場合にのみ含める
2. `/git-commit` を実行する（`issue_number=<N>`, `allowed_types=[feat, fix, refactor, chore, style, test, docs]`）
3. 作業内容を issue のコメントとして投稿する
4. ユーザー確認なしに即座に Phase 2 へ進む

根拠: `commands/task.md:123-131`

### Phase 2: PR 本文の準備

ガード: main 以外のブランチ、コミットが 1 件以上存在、ワークスペースがクリーンであること。worktree 隔離セッションの場合、`commands/work.md` G-2 と同じ manifest 突き合わせ（`hooks/lib/session-paths.sh session-tmp-dir` で解決した `worktree-untracked-symlinks.txt` と `git status` を比較し、完全一致またはその親ディレクトリのエントリを除外）をクリーン判定の前に行う（issue #318）。

実行 agent に応じた `${TEMPLATES_DIR}/pr.md`（Claude Code は `~/.claude/templates`、Codex CLI は `~/.codex/templates`）を使って英語で PR 本文・タイトルを作成し、session temp directory に `pr-title.txt` と `pr-body.md` を書き出す。この時点では push も PR 作成も行わない。PR タイトルは `<type>(#<issue-number>): <description>` 形式とし、PR 全体の主目的から許可済み Conventional Commit type を選んで primary implementation commit と揃える。description も PR 全体の目的と primary implementation commit に整合させ、commit 数にかかわらず同じ形式を使う。

`Specific docs sections to update` フィールドには、Phase 1 Step 1 の投資調査で `docs/L3_implementation/specification_summary.md` を読んだ際に確認済みのセクション見出しの行範囲を `docs/L3_implementation/specification_summary.md:<line-range>` の citation 形式で書く（再度 Read して探し直さない）。`/docs-sync` Phase 1 Step 2 がこの citation を解析し、Phase 2 で該当箇所を対象読みして再利用する（issue #307）。特定していない場合はファイル名・説明文で代替する。

ユーザーに「追加の変更はありますか？」と確認し、なければ `/docs-sync` を自動実行する。`/docs-sync` 完了後、ユーザー確認なしに即座に `/git-pr` を実行する（push → PR 作成まで完結）。

`/git-pr` による ready PR 作成が task フローのゴールである。作成後の review・merge は自動実行しない（人間、または `/review-resolve`・`/codex-review` を手動起動するユーザーが行う）。

根拠: `commands/task.md:149-190`

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

### `hooks/lib/session-paths.sh` 経由でパスを解決する理由（issue #316）

上記の直接導出方式は、`SESSION_ID="${CLAUDE_CODE_KIT_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-}}"` のような brace expansion と、代入への command substitution（`$(...)`）を含む Bash スニペットとして Step 2 / Phase 2 Step 1 にインライン展開されていた。`/work-multi` の worktree 隔離セッションでは、Claude Code harness がこのスニペットを「worktree の外に影響しないか静的に検証できない」として拒否することが判明した（この repo の hooks とは独立した harness 自身の安全策）。対策として解決ロジックを `hooks/lib/session-paths.sh` に集約し、Step 2 / Phase 2 Step 1 は `bash ~/.claude/hooks/lib/session-paths.sh <session-approved|session-tmp-dir>` という brace expansion も代入への command substitution も含まない単一のプレーンな呼び出しのみを行う。詳細は `docs/L3_implementation/hooks/lib/session-paths.sh.md` を参照。

### Phase 2 クリーン判定で manifest を突き合わせる理由（issue #318）

`scripts/link-worktree-untracked.sh` が worktree 隔離セッション向けに作成する symlink は `.gitignore` のディレクトリ限定パターンに一致せず `git status` に `??`/`!!` として現れる。突き合わせずに従来の「クリーンでなければ stash」ロジックだけを適用すると、無害な symlink 群が毎回 stash され、後続処理で意図せず退避されるリスクがある。`hooks/lib/session-paths.sh session-tmp-dir` は Phase 2 Step 1 で PR 本文の書き出し先としてどのみち解決するため、同じ session tmp directory 配下の manifest を読むだけで追加の依存を増やさずに対応できる。

## 統合ポイント

- 呼び出し元: `commands/work.md`（ルーティング判定後）、`commands/patch.md`（エスカレーション時）
- 呼び出すもの: `commands/new-issue.md`（Step 4-5 のみ）、`/git-commit`、`commands/docs-sync.md`、`commands/git-pr.md`、`hooks/lib/session-paths.sh`（`bash` で直接実行、`source` はしない）
- Claude Code の会話スレッド: 作業ブランチの切替直後に、agent 別の分岐で `~/.claude/scripts/rename-thread.sh` を使い現在のブランチ名へ更新する
- Phase 2 クリーン判定の manifest: `scripts/link-worktree-untracked.sh` が書き出す `worktree-untracked-symlinks.txt`（issue #318）
- PR テンプレート: `${TEMPLATES_DIR}/pr.md`（Phase 2 で temp ファイルに書き出す）
- issue テンプレート: `${TEMPLATES_DIR}/issue.md`
- template root: Claude Code は `~/.claude/templates`、Codex CLI は `~/.codex/templates`

## 注意事項

- ソースコードを修正する場合は修正前に言語対応の coding コマンド（`commands/coding-*.md`）を Read する。JSX/TSXではReact layerを追加し、`next` dependencyまたはNext.js configがあるprojectではさらにNext.js layerを追加する。
- `session-approved` に L3 per-file doc パスを含めないと hook がブロックするため、Step 2 で必ず含める
- task.md は docs-sync.md を自動実行し（Phase 2 Step 1）、完了後に git-pr.md を自動実行する。docs-sync の HARD STOP 時はユーザーへ報告して終了し、git-pr は実行しない
- `rename-thread.sh` は Claude Code の session transcript を更新する補助スクリプトであり、Codex CLI の会話には適用しない

## 変更履歴（git log より自動生成）

- ccd9fe3 wip: 2026-08-14 01:31:37 before apply_patch
- 0331e9e feat(#336): rename thread on work branch switch
- 1aa3c2d fix(#318): distinguish worktree-untracked symlinks from real changes via manifest
- e7d5698 fix(#316): resolve session paths via hooks/lib/session-paths.sh to survive worktree-isolated harness guard
- 5e9bc3f feat(#307): carry specification_summary.md citations from /task to /docs-sync
- c5776f2 feat(#297): scope tool:gh_issue_write/tool:gh_pr_write session grants to issue/PR number
- 1146f95 feat(#286): add generic React and Next.js guidelines
- d4bd418 feat(#267): add /coding-sh command and enforce shellcheck across all shell scripts
- e4b3d18 fix: apply resolve-then-embed to task.md session tmp dir mkdir
- db6d6c3 fix(#210): resolve session id from env instead of a shared pointer file
- 5a4ecc6 chore(#205): remove /pr-review; /work and /task now end at PR creation
