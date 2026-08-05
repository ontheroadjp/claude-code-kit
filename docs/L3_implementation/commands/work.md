# `commands/work.md`

## 目的・役割

通常作業の入口として、main branch への切り替え、workspace gate、リポジトリ調査、後続 workflow へのルーティングを担う。

根拠: `commands/work.md:1-40`

## 動作概要

issue 番号が指定された場合は、実装向け調査より先に issue labels を取得する。name が `report` と完全一致する label があれば `commands/report-review.md` に委譲して終了し、実装 branch や `/task`・`/patch` flow には進まない。report label がない issue は既存どおり issue 起点の `/task` へ進み、issue がない作業は docs 変更の要否によって `/task` または `/patch` に分岐する。

根拠: `commands/work.md:46-112`

非 main branch で再開した場合は workspace と main 以降の commit の有無から task の再開地点を決め、調査結果と開始 phase をユーザーへ提示する。

根拠: `commands/work.md:114-140`

## 重要な設計判断

- report 判定は label name の完全一致とし、類似名による read-only workflow への誤配送を避ける。
- report routing を実装向け現状調査より前に置き、評価だけを求める issue に implementation planning を適用しない。
- label 取得に失敗した場合は推測で既存 flow に進まず、安全に停止する。
- G-0 は `git checkout main` のみを行い、`session-approved` には一切触れない（issue #261 で従来の防御的クリアを廃止）。過去の経緯は以下の通り:
    - 当初は前回 `/work` 呼び出しの承認状態を毎回クリアする目的で、G-0 が `session-approved` へ空文字列を書き込んでいた。パス解決は `$CLAUDE_CODE_SESSION_ID`（Codex は `$CODEX_THREAD_ID` のハッシュ）から自セッションの `session-approved` パスを直接導出する方式（issue #210 で、複数セッション同時実行時に他セッションのファイルを誤って参照する競合を避けるため、共有ポインタファイル経由から変更）。
    - クリア手段に Bash の `rm -f` ではなく Write ツールでの空文字列書き込みを選んでいたのは issue #227 の判断による。`rm -f "$SESSION_APPROVED"` は対象パスが変数経由である限り hook の静的テキスト判定では安全性を保証できず常に確認プロンプトへ落ちるが、Write ツールの `is_session_approved_path` は書き込み先を hook 自身が独立に再計算し、内容が空または既存より狭い場合は無条件承認する仕組みを持つため、これを再利用して確認プロンプトを回避していた。issue #248 で hook 側に `rm [-f] <literal-path>` の自動承認（`is_rm_f_on_safe_literal_path`）が追加された後も、追加の Bash 呼び出しを避ける理由で Write 方式を維持していた。
    - `/report-review #261` で、この空書き込みが `hooks/auto-approve-readonly.sh` の Write ハンドラの「ファイルが absent の場合のみ無条件承認」という初回書き込み判定と衝突することが判明した。`hooks/cleanup-session.sh`（Stop hook）が正常に `session-approved` を削除済み（absent）であっても、G-0 の空書き込みがそれを「exists-empty」状態に変換してしまい、直後の `task.md`/`patch.md` Step 2 の実承認内容の書き込みが既存内容（空）との差分比較で毎回確実にスコープ拡大としてブロックされていた。Stop hook の削除失敗の有無に依存しない決定論的な不具合だった。
    - 対処として `rm -f` への回帰も検討したが不採用とした。commit 87ce937（fix #250）は `session-approved` を `rm -f` の自動承認対象から明示的に除外している（`is_rm_protected_path`）。これはエージェントが確認なしにスコープガードのベースラインをリセットできる抜け穴（過去に許可された実際のスコープを、確認なしに削除→再構築で置き換える）を塞ぐためのものであり、G-0 を `rm -f` に戻すとこの抜け穴を「レアケースの救済」としてではなく「通常フローで毎回」再開放することになる。同じ理由で、hook 側の Write ハンドラを「既存内容が空なら absent と同等に扱う」よう変更する案（`Write` 経由で同種の抜け穴が開く）も不採用とした。
    - 最終的に、G-0 の防御的クリア自体を削除する方針を採った。Stop hook が正常に動作している通常ケースでは `session-approved` は既に absent であり、G-0 が何もしなくても Step 2 の書き込みが自然に初回書き込みとして無条件承認される。Stop hook が削除に失敗していた場合（真にイレギュラーなケース）のみ、Step 2 の書き込みが既存のスコープ拡大チェックにそのまま委ねられ、通常の確認プロンプトにフォールスルーする（新しい自動承認ロジックは追加しない）。

根拠: `commands/work.md:9-13`, `hooks/lib/session-id.sh`, `hooks/auto-approve-readonly.sh`（Write ハンドラの `session-approved` 判定）, issue #210, issue #227, issue #248, issue #250, issue #261

## 統合ポイント

- report issue: `commands/report-review.md`
- issue 起点または docs 変更あり: `commands/task.md`
- issue なし、docs 変更なし: `commands/patch.md`
- 調査起点: `docs/.ai/repo.profile.json` の `primary_docs`

## 注意事項・既知の制限

- report routing はユーザーが issue 番号を明示した新規作業で適用される。
- `/work` 自体の workspace gate は report 判定より先に実行される。

## 変更履歴（git log より自動生成）

- af81df0 fix(#262): remove G-0's defensive empty-write to session-approved
- ade5abd feat(#248): add literal-path rm auto-approval and resolve-then-embed convention
- 1e3b7fa fix(#227): avoid rm -f confirmation prompt in /work G-0 by clearing session-approved via Write tool
- db6d6c3 fix(#210): resolve session id from env instead of a shared pointer file
- 0297a81 feat(#126): add report review workflow
- 028b3af fix(#136): announce session-approved path from hook so Claude can locate it
- 13dbefd refactor: reduce duplicate file reads across work/task/patch/codex-review flows
- dd29feb feat(#129): store session approvals per session
- ab4370b fix(#119): explicitly skip Step 3 and jump to Phase 2 on resume
- 26036e6 fix(#119): reset session-approved at G-0 and route resume to Step 2

根拠: `commands/work.md:9-140`
