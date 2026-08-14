# `commands/work.md`

## 目的・役割

実装作業の入口として、main branch への切り替え、workspace gate、リポジトリ調査、後続 workflow へのルーティングを担う。

根拠: `commands/work.md:1-46`

## 動作概要

G-0 は `git rev-parse --show-toplevel` が `.claude/worktrees/` を含むかを先に判定し、含む場合（`EnterWorktree` が作成した worktree 内、例: `/work-multi`）は `git checkout main` をスキップする。含まない場合は従来どおり `git checkout main` を実行する（issue #296、`commands/work.md:9-13`）。

G-2 のワークスペース確認は、worktree 隔離セッションの場合、`hooks/lib/session-paths.sh session-tmp-dir` で解決した session tmp directory 配下の `worktree-untracked-symlinks.txt`（存在する場合）と `git status --porcelain` の出力を突き合わせ、manifest に列挙されたパスと完全一致またはその親ディレクトリであるエントリを除外してから「差分があるか」を判定する。`scripts/link-worktree-untracked.sh` が作成した symlink は `.gitignore` のディレクトリ限定パターンに一致せず `??`/`!!` として現れるための対処（issue #318）。manifest が存在しない場合は従来通り `git status` の出力をそのまま扱う。

issue 番号が指定された場合は、実装向け調査より先に issue labels を取得する。name が `agenda` と完全一致する label があれば `commands/mtg.md` に委譲して終了し、実装 branch や `/task`・`/patch` flow には進まない。`agenda` に該当せず `hazard-candidate` と完全一致する label がある場合は、`/triage-issues-for-hazard` の実行を促すメッセージを出して `/work` を終了する。どちらの label にも該当しない issue は既存どおり issue 起点の `/task` へ進み、issue がない作業は docs 変更の要否によって `/task` または `/patch` に分岐する。

「Step 2. 現状調査」の冒頭には、この調査フェーズで許可される手段（Read・Grep・Glob・WebFetch・WebSearch・`gh` の読み取り専用呼び出し）と、Edit・Write（session-tmp・session-approved ファイルを除く）は task.md/patch.md の Step 2 プラン承認まで実行してはならない旨を明示するガード文がある（issue #356）。WebFetch・WebSearch は調査目的の読み取りに限定し、web 上の素材のダウンロード・取得や外部サービスへの書き込みなど「現状変更」を伴う操作を一切禁止する一文、および禁止事項に該当する操作が調査上どうしても必要な場合は理由をユーザーに報告し実行可否の判断を仰ぐ旨のエスケープハッチ文が追加されている（issue #358）。

根拠: `commands/work.md:60-63`, `commands/work.md:90-123`

(A)/(B) のルーティング判定は、現在ブランチが `main` 自身、または `EnterWorktree` が作成する固定 prefix `worktree-` で始まる場合のみ (A) 新規作業とし、それ以外の全ての非 main ブランチは (B) 再開・エスカレーション（既存の B.1/B.2/B.3 判定）として扱う（issue #296、PR #304 レビューで修正）。

根拠: `commands/work.md:51-56`

非 main branch で再開した場合は workspace と main 以降の commit の有無から task の再開地点を決め、調査結果と開始 phase をユーザーへ提示する。

根拠: `commands/work.md:160-176`

## 重要な設計判断

- 現状調査における候補ファイルの Read は、対応する L3 per-file doc（`docs/L3_implementation/<path>.md`）が存在する場合、その doc の `根拠: <file>:<line-range>` citation を先に確認し、候補ファイル本体は該当行範囲の対象読み（`offset`/`limit`）に絞る。L3 doc がない、または対象箇所を特定できない場合のみ従来通り直接 Read する。`/analyze-access` の集計で、L3 doc を持つ大きいファイル（例: `hooks/auto-approve-readonly.sh`）がセッション内で繰り返しフル Read され、重複読み込みロスの大半を占めていたことが判明したための対処（issue #269）。
- 「現状調査」の手順本文は (A)・(B) 両分岐で一字一句同一だったため、`## 開始判定とルーティング` 直下の「Step 2. 現状調査」に1箇所だけ定義する（issue #271）。(B) 側は独立見出し `#### 現状調査` の下に「上記の Step 2（現状調査）を実行する」という参照文を持つ。(A) 側は独立見出しを持たず、「親 issue ではなく、いずれの label にも該当しない場合」の分岐結果として「上記の Step 2（現状調査）を実行してから 2段階ルーティングへ進む」という一文で同じ参照を行う（issue #360）。分岐固有の実行タイミング（ルーティング判定の前 / 開始フェーズ報告の前）は、この参照文自体の文言に含める。
- agenda / hazard-candidate 判定は label name の完全一致とし、類似名による誤配送を避ける。
- agenda・hazard-candidate の label routing を実装向け現状調査より前に置き、方針・実装境界が未決の issue や人間のハザード審査を経ていない issue に implementation planning を適用しない。
- label 取得に失敗した場合は推測で既存 flow に進まず、安全に停止する。
- `hooks/auto-approve-readonly.sh` は working-repo 内の Edit/Write を `is_in_working_repo` → `do_wip_commit` 経由で無条件承認する（issue #148）ため、調査フェーズでの Edit/Write を止める technical gate は存在しない。唯一の防御は work.md/task.md/patch.md の手順順序という behavioral gate であり、それ自体を明文化した禁止がどこにもなかった。issue 番号明示時の親子issue・label 事前ルーティングが拡大し「現状調査（共通）」に到達するまでの区間が長くなったことが引き金となり、ユーザーから調査フェーズ中の意図しない編集が報告された（issue #356）。対処として「現状調査（共通）」冒頭に、この段階で許可される手段（Read/Grep/Glob/WebFetch/WebSearch/`gh` 読み取り専用呼び出し）と Edit/Write 禁止を明示するガード文を追加した。
- WebFetch・WebSearch は `hooks/auto-approve-readonly.sh` の対象外（同 hook が扱うのは Bash・Edit・Write のみ）であり、Edit/Write と同様に technical gate が存在しない。issue #356 のガード文はこれらを「許可される読み取り専用手段」として一括で列挙していたが、web 由来の素材のダウンロード・取得や外部サービスへの書き込みを明示的に禁止していなかったため、この抜け穴を塞ぐ一文を追加した（issue #358）。さらに、禁止事項に該当する操作が調査上どうしても必要になるケース（真に読み取りだけでは調査を完了できない場合）を想定し、無断実行ではなくユーザーへの理由報告と実行可否確認を経由する運用上のエスケープハッチを明文化した。これも behavioral gate であり、technical な強制力は持たない。
- hazard-candidate チェックは `/analyze-hazard-scan` が起票した issue に対し `/work #N` を直接叩くと、`/triage-issues-for-hazard` のハザード分析開示・yes/no 確認を一切経由せず実装まで進んでしまう問題への対処である。`/triage-issues-for-hazard` で `yes` と回答された issue は `hazard-candidate` → `triage-approved` へ label が swap されるため、このチェックには再度ひっかからず通常の `/task` ルーティングに進める。
- worktree パスガードと (A)/(B) のブランチ分類変更は `/work-multi`（issue #296）が `commands/work.md` を無改変のまま実行するとの前提で設計されたが、実機検証で `git checkout main` が worktree 内では `fatal: 'main' is already used by worktree` で必ず失敗することが判明し、この前提は成立しなかった。パスガードは、失敗してからエラー文言を解釈するのではなく `.claude/worktrees/` という `EnterWorktree` 自身の固定仕様を事前チェックすることで確実に判定する設計とした。
- (A)/(B) 分類は当初「`/task`・`/patch` が実際に作成する命名規則（`feat/` 等）に一致するか」で判定していたが、PR #304 の Codex CLI レビューで、この基準だとユーザーが手動で作成した命名規則に沿わないブランチ（例: `docs/foo`）上で未コミット変更がある状態から `git checkout main` が失敗した場合、既存の B.1（未コミット変更があれば継続）に到達せず誤って (A) 新規作業に分類されてしまう問題を指摘された。修正後は分類基準を `worktree-` prefix の有無だけに限定し、それ以外の非 main ブランチは全て従来通り (B) の B.1/B.2/B.3 判定に委ねることで、既存の「未コミット変更があれば継続」という安全な挙動を保持しつつ、fresh worktree のブランチ（`worktree-<name>`）だけを (A) 新規作業として扱う。
- G-0 は（worktree パスガードによるスキップ判定を除き）`git checkout main` のみを行い、`session-approved` には一切触れない（issue #261 で従来の防御的クリアを廃止）。過去の経緯は以下の通り:
    - 当初は前回 `/work` 呼び出しの承認状態を毎回クリアする目的で、G-0 が `session-approved` へ空文字列を書き込んでいた。パス解決は `$CLAUDE_CODE_SESSION_ID`（Codex は `$CODEX_THREAD_ID` のハッシュ）から自セッションの `session-approved` パスを直接導出する方式（issue #210 で、複数セッション同時実行時に他セッションのファイルを誤って参照する競合を避けるため、共有ポインタファイル経由から変更）。
    - クリア手段に Bash の `rm -f` ではなく Write ツールでの空文字列書き込みを選んでいたのは issue #227 の判断による。`rm -f "$SESSION_APPROVED"` は対象パスが変数経由である限り hook の静的テキスト判定では安全性を保証できず常に確認プロンプトへ落ちるが、Write ツールの `is_session_approved_path` は書き込み先を hook 自身が独立に再計算し、内容が空または既存より狭い場合は無条件承認する仕組みを持つため、これを再利用して確認プロンプトを回避していた。issue #248 で hook 側に `rm [-f] <literal-path>` の自動承認（`is_rm_f_on_safe_literal_path`）が追加された後も、追加の Bash 呼び出しを避ける理由で Write 方式を維持していた。
    - `/report-review #261` で、この空書き込みが `hooks/auto-approve-readonly.sh` の Write ハンドラの「ファイルが absent の場合のみ無条件承認」という初回書き込み判定と衝突することが判明した。`hooks/cleanup-session.sh`（Stop hook）が正常に `session-approved` を削除済み（absent）であっても、G-0 の空書き込みがそれを「exists-empty」状態に変換してしまい、直後の `task.md`/`patch.md` Step 2 の実承認内容の書き込みが既存内容（空）との差分比較で毎回確実にスコープ拡大としてブロックされていた。Stop hook の削除失敗の有無に依存しない決定論的な不具合だった。
    - 対処として `rm -f` への回帰も検討したが不採用とした。commit 87ce937（fix #250）は `session-approved` を `rm -f` の自動承認対象から明示的に除外している（`is_rm_protected_path`）。これはエージェントが確認なしにスコープガードのベースラインをリセットできる抜け穴（過去に許可された実際のスコープを、確認なしに削除→再構築で置き換える）を塞ぐためのものであり、G-0 を `rm -f` に戻すとこの抜け穴を「レアケースの救済」としてではなく「通常フローで毎回」再開放することになる。同じ理由で、hook 側の Write ハンドラを「既存内容が空なら absent と同等に扱う」よう変更する案（`Write` 経由で同種の抜け穴が開く）も不採用とした。
    - 最終的に、G-0 の防御的クリア自体を削除する方針を採った。Stop hook が正常に動作している通常ケースでは `session-approved` は既に absent であり、G-0 が何もしなくても Step 2 の書き込みが自然に初回書き込みとして無条件承認される。Stop hook が削除に失敗していた場合（真にイレギュラーなケース）のみ、Step 2 の書き込みが既存のスコープ拡大チェックにそのまま委ねられ、通常の確認プロンプトにフォールスルーする（新しい自動承認ロジックは追加しない）。

根拠: `commands/work.md:9-13`, `commands/work.md:51-56`, `commands/work.md:60-63`, `commands/work.md:90-123`, `commands/work.md:160-176`, `hooks/lib/session-id.sh`, `hooks/auto-approve-readonly.sh`（Write ハンドラの `session-approved` 判定、Edit/Write working-repo 無条件承認）, issue #148, issue #210, issue #227, issue #248, issue #250, issue #261, issue #269, issue #271, issue #296, issue #298, issue #318, issue #356, issue #360, PR #304

## 統合ポイント

- agenda issue: `commands/mtg.md`
- hazard-candidate issue: `/triage-issues-for-hazard` の実行を案内して終了（`/work` は呼ばない）
- issue 起点または docs 変更あり: `commands/task.md`
- issue なし、docs 変更なし: `commands/patch.md`
- 調査起点: `docs/.ai/repo.profile.json` の `primary_docs`
- worktree 隔離入口: `commands/work-multi.md`（`EnterWorktree` で worktree に切り替えた後、この `commands/work.md` を無改変のまま Read して実行する。issue #296）
- G-2 の manifest 突き合わせ: `hooks/lib/session-paths.sh`（`bash` で直接実行）、`scripts/link-worktree-untracked.sh` が書き出す `worktree-untracked-symlinks.txt`（issue #318）

## 注意事項・既知の制限

- agenda / hazard-candidate の label routing はユーザーが issue 番号を明示した新規作業で適用される。
- `/work` 自体の workspace gate は label 判定より先に実行される。
- hazard-candidate チェックは label の完全一致にのみ依存するため、人間が `gh label` を直接操作して label を付け替えればこのゲートは迂回できる。agenda label ゲートも同じ前提で運用される。
- worktree パスガードは `.claude/worktrees/` という固定パスにのみ依存する。`EnterWorktree` 以外の手段（例: 手動の `git worktree add`）でこのパス規約に従わない worktree を作った場合はガードが機能せず、通常の `git checkout main` が試行される。

## 変更履歴（git log より自動生成）

- ae1c7f9 fix(#360): align /work heading wording and (A)/(B) investigation references
- e501904 #358 Prohibit web write/download during /work investigation phase (#359)
- 4ddff6e #356 Prohibit edits during /work investigation phase (#357)
- f484a2d Route parent issues to their next ready child (#351)
- 446c4d3 #343 Replace report review with human-led mtg agendas (#345)
- ea565ac #326 Automate worktree symlink status filtering (#327)
- a46be53 feat(#321): unify operational hazard workflows
- 1aa3c2d fix(#318): distinguish worktree-untracked symlinks from real changes via manifest
- 69c1e80 fix(#296): use worktree- prefix only for branch classification and NUL-delimited untracked enumeration
- bc4ae7b feat(#296): add /work-multi worktree-isolated entry point

根拠: `commands/work.md:9-176`
