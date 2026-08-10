# `commands/work.md`

## 目的・役割

通常作業の入口として、main branch への切り替え、workspace gate、リポジトリ調査、後続 workflow へのルーティングを担う。

根拠: `commands/work.md:1-40`

## 動作概要

G-0 は `git rev-parse --show-toplevel` が `.claude/worktrees/` を含むかを先に判定し、含む場合（`EnterWorktree` が作成した worktree 内、例: `/work-multi`）は `git checkout main` をスキップする。含まない場合は従来どおり `git checkout main` を実行する（issue #296、`commands/work.md:9-15`）。

issue 番号が指定された場合は、実装向け調査より先に issue labels を取得する（`gh issue view <N> --json labels` を1回だけ呼び出し、以下2つの判定を同じ結果に対して行う）。name が `report` と完全一致する label があれば `commands/report-review.md` に委譲して終了し、実装 branch や `/task`・`/patch` flow には進まない。`report` に該当せず `auto-approve-candidate` と完全一致する label がある場合は、`/triage-issues-for-auto-approve` の実行を促すメッセージを出して `/work` を終了し、`/task`・`/patch` へのルーティングやブランチ作成は行わない（issue #298）。どちらの label にも該当しない issue は既存どおり issue 起点の `/task` へ進み、issue がない作業は docs 変更の要否によって `/task` または `/patch` に分岐する。

根拠: `commands/work.md:60-121`

(A)/(B) のルーティング判定は「現在ブランチが `main` か」の単純比較ではなく、「`/task`・`/patch` が作業ブランチに使う命名規則（`feat/`, `change/`, `fix/`, `test/`, `chore-`, `patch/`）のいずれかに一致するか」で行う。一致すれば (B) 再開・エスカレーション、一致しなければ（`main` 自身、および `worktree-` prefix のブランチを含む）(A) 新規作業として扱う（issue #296）。

根拠: `commands/work.md:48-58`

非 main branch で再開した場合は workspace と main 以降の commit の有無から task の再開地点を決め、調査結果と開始 phase をユーザーへ提示する。

根拠: `commands/work.md:118-135`

## 重要な設計判断

- 現状調査における候補ファイルの Read は、対応する L3 per-file doc（`docs/L3_implementation/<path>.md`）が存在する場合、その doc の `根拠: <file>:<line-range>` citation を先に確認し、候補ファイル本体は該当行範囲の対象読み（`offset`/`limit`）に絞る。L3 doc がない、または対象箇所を特定できない場合のみ従来通り直接 Read する。`/analyze-access` の集計で、L3 doc を持つ大きいファイル（例: `hooks/auto-approve-readonly.sh`）がセッション内で繰り返しフル Read され、重複読み込みロスの大半を占めていたことが判明したための対処（issue #269）。
- 「現状調査」の手順本文は (A)・(B) 両分岐で一字一句同一だったため、`## 開始判定とルーティング` 直下の「現状調査（共通）」に1箇所だけ定義し、(A)・(B) 側は「上記「現状調査（共通）」を実行する」という参照のみを持つ（issue #271）。分岐固有の実行タイミング（ルーティング判定の前 / 開始フェーズ報告の前）だけを各参照側の一文に残す。
- report / auto-approve-candidate 判定は label name の完全一致とし、類似名による誤配送を避ける。
- report・auto-approve-candidate の label routing を実装向け現状調査より前に置き、評価だけを求める issue や人間のハザード審査を経ていない issue に implementation planning を適用しない。
- label 取得に失敗した場合は推測で既存 flow に進まず、安全に停止する。
- auto-approve-candidate チェックは `/auto-approve-hazard-scan` が起票した issue に対し `/work #N` を直接叩くと、`/triage-issues-for-auto-approve` のハザード分析開示・yes/no 確認を一切経由せず実装まで進んでしまう問題への対処として追加した（issue #298）。`/triage-issues-for-auto-approve` で `yes` と回答された issue は `auto-approve-candidate` → `triage-approved` へ label が swap されるため、このチェックには再度ひっかからず通常の `/task` ルーティングに進める。
- worktree パスガードと (A)/(B) のブランチ命名規則ベース分類は `/work-multi`（issue #296）が `commands/work.md` を無改変のまま実行するとの前提で設計されたが、実機検証で `git checkout main` が worktree 内では `fatal: 'main' is already used by worktree` で必ず失敗することが判明し、この前提は成立しなかった。パスガードは、失敗してからエラー文言を解釈するのではなく `.claude/worktrees/` という `EnterWorktree` 自身の固定仕様を事前チェックすることで確実に判定する設計とした。ブランチ分類の変更は、worktree パスガードだけを追加すると fresh worktree のブランチ（`worktree-<name>`）が (B) 側の「それ以外」に落ち、`/task`・`/patch` の本来のルーティング判定（issue 起点か・docs 変更要否か）が常にスキップされてしまう問題への対処。既存の `/task`・`/patch` が作成するブランチは全て決まった命名規則を使うため、この命名規則に一致するかで分類基準を置き換えても既存の (B) 判定結果は変わらない（通常の非 worktree checkout では `git checkout main` は workspace が clean であれば常に成功し、ブランチは必ず文字通り `main` になることを実機で確認済み）。
- G-0 は（worktree パスガードによるスキップ判定を除き）`git checkout main` のみを行い、`session-approved` には一切触れない（issue #261 で従来の防御的クリアを廃止）。過去の経緯は以下の通り:
    - 当初は前回 `/work` 呼び出しの承認状態を毎回クリアする目的で、G-0 が `session-approved` へ空文字列を書き込んでいた。パス解決は `$CLAUDE_CODE_SESSION_ID`（Codex は `$CODEX_THREAD_ID` のハッシュ）から自セッションの `session-approved` パスを直接導出する方式（issue #210 で、複数セッション同時実行時に他セッションのファイルを誤って参照する競合を避けるため、共有ポインタファイル経由から変更）。
    - クリア手段に Bash の `rm -f` ではなく Write ツールでの空文字列書き込みを選んでいたのは issue #227 の判断による。`rm -f "$SESSION_APPROVED"` は対象パスが変数経由である限り hook の静的テキスト判定では安全性を保証できず常に確認プロンプトへ落ちるが、Write ツールの `is_session_approved_path` は書き込み先を hook 自身が独立に再計算し、内容が空または既存より狭い場合は無条件承認する仕組みを持つため、これを再利用して確認プロンプトを回避していた。issue #248 で hook 側に `rm [-f] <literal-path>` の自動承認（`is_rm_f_on_safe_literal_path`）が追加された後も、追加の Bash 呼び出しを避ける理由で Write 方式を維持していた。
    - `/report-review #261` で、この空書き込みが `hooks/auto-approve-readonly.sh` の Write ハンドラの「ファイルが absent の場合のみ無条件承認」という初回書き込み判定と衝突することが判明した。`hooks/cleanup-session.sh`（Stop hook）が正常に `session-approved` を削除済み（absent）であっても、G-0 の空書き込みがそれを「exists-empty」状態に変換してしまい、直後の `task.md`/`patch.md` Step 2 の実承認内容の書き込みが既存内容（空）との差分比較で毎回確実にスコープ拡大としてブロックされていた。Stop hook の削除失敗の有無に依存しない決定論的な不具合だった。
    - 対処として `rm -f` への回帰も検討したが不採用とした。commit 87ce937（fix #250）は `session-approved` を `rm -f` の自動承認対象から明示的に除外している（`is_rm_protected_path`）。これはエージェントが確認なしにスコープガードのベースラインをリセットできる抜け穴（過去に許可された実際のスコープを、確認なしに削除→再構築で置き換える）を塞ぐためのものであり、G-0 を `rm -f` に戻すとこの抜け穴を「レアケースの救済」としてではなく「通常フローで毎回」再開放することになる。同じ理由で、hook 側の Write ハンドラを「既存内容が空なら absent と同等に扱う」よう変更する案（`Write` 経由で同種の抜け穴が開く）も不採用とした。
    - 最終的に、G-0 の防御的クリア自体を削除する方針を採った。Stop hook が正常に動作している通常ケースでは `session-approved` は既に absent であり、G-0 が何もしなくても Step 2 の書き込みが自然に初回書き込みとして無条件承認される。Stop hook が削除に失敗していた場合（真にイレギュラーなケース）のみ、Step 2 の書き込みが既存のスコープ拡大チェックにそのまま委ねられ、通常の確認プロンプトにフォールスルーする（新しい自動承認ロジックは追加しない）。

根拠: `commands/work.md:9-15`, `commands/work.md:48-58`, `commands/work.md:78-97`, `commands/work.md:136-152`, `hooks/lib/session-id.sh`, `hooks/auto-approve-readonly.sh`（Write ハンドラの `session-approved` 判定）, issue #210, issue #227, issue #248, issue #250, issue #261, issue #269, issue #271, issue #296, issue #298

## 統合ポイント

- report issue: `commands/report-review.md`
- auto-approve-candidate issue: `/triage-issues-for-auto-approve` の実行を案内して終了（`/work` は呼ばない）
- issue 起点または docs 変更あり: `commands/task.md`
- issue なし、docs 変更なし: `commands/patch.md`
- 調査起点: `docs/.ai/repo.profile.json` の `primary_docs`
- worktree 隔離入口: `commands/work-multi.md`（`EnterWorktree` で worktree に切り替えた後、この `commands/work.md` を無改変のまま Read して実行する。issue #296）

## 注意事項・既知の制限

- report / auto-approve-candidate の label routing はユーザーが issue 番号を明示した新規作業で適用される。
- `/work` 自体の workspace gate は label 判定より先に実行される。
- auto-approve-candidate チェックは label の完全一致にのみ依存するため、人間が `gh label` を直接操作して label を付け替えればこのゲートは迂回できる。既存の report label ゲートも同じ前提で運用されており、一貫性のある許容範囲として扱う。
- worktree パスガードは `.claude/worktrees/` という固定パスにのみ依存する。`EnterWorktree` 以外の手段（例: 手動の `git worktree add`）でこのパス規約に従わない worktree を作った場合はガードが機能せず、通常の `git checkout main` が試行される。

## 変更履歴（git log より自動生成）

- 4450e96 feat(#298): gate /work on auto-approve-candidate label, swap to triage-approved on approval
- 5722f08 feat(#271): add deterministic docs-sync CI rule, wire approval hook tests into CI, dedupe work.md investigation text
- b3a5b06 chore(#269): prefer L3 doc line citations over full-file reads in /work investigation
- af81df0 fix(#262): remove G-0's defensive empty-write to session-approved
- ade5abd feat(#248): add literal-path rm auto-approval and resolve-then-embed convention
- 1e3b7fa fix(#227): avoid rm -f confirmation prompt in /work G-0 by clearing session-approved via Write tool
- db6d6c3 fix(#210): resolve session id from env instead of a shared pointer file
- 0297a81 feat(#126): add report review workflow
- 028b3af fix(#136): announce session-approved path from hook so Claude can locate it
- 13dbefd refactor: reduce duplicate file reads across work/task/patch/codex-review flows

根拠: `commands/work.md:9-149`
