# `commands/work.md`

## 目的・役割

通常作業の入口として、main branch への切り替え、workspace gate、リポジトリ調査、後続 workflow へのルーティングを担う。

根拠: `commands/work.md:1-47`

## 動作概要

issue 番号が指定された場合は、実装向け調査より先に issue labels を取得する。name が `report` と完全一致する label があれば `commands/report-review.md` に委譲して終了し、実装 branch や `/task`・`/patch` flow には進まない。report label がない issue は既存どおり issue 起点の `/task` へ進み、issue がない作業は docs 変更の要否によって `/task` または `/patch` に分岐する。

根拠: `commands/work.md:49-115`

非 main branch で再開した場合は workspace と main 以降の commit の有無から task の再開地点を決め、調査結果と開始 phase をユーザーへ提示する。

根拠: `commands/work.md:117-143`

## 重要な設計判断

- report 判定は label name の完全一致とし、類似名による read-only workflow への誤配送を避ける。
- report routing を実装向け現状調査より前に置き、評価だけを求める issue に implementation planning を適用しない。
- label 取得に失敗した場合は推測で既存 flow に進まず、安全に停止する。
- G-0 の前回承認状態クリアは `$CLAUDE_CODE_SESSION_ID`（Codex は `$CODEX_THREAD_ID` のハッシュ）から自セッションの `session-approved` パスを直接導出する。以前は `${STATE_ROOT}/current-session-approved-path` という共有ポインタファイルを読んで導出していたが、複数セッション同時実行時に他セッションのファイルを誤って参照する競合があったため（issue #210）、共有ファイルを経由しない方式に変更した。
- クリア自体は Bash の `rm -f` ではなく Write ツールで空文字列を書き込む方式にしている（issue #227）。`hooks/auto-approve-readonly.sh` はセグメントを独立に静的テキスト判定するため、`rm -f "$SESSION_APPROVED"` の対象パスが変数経由である以上、直前の代入セグメントで値を差し替えられても検出できず安全性を保証できない。そのため hook は常にこの `rm` を確認プロンプトへ落としていた。一方 Write ツールの `is_session_approved_path` は書き込み先を hook 自身が独立に再計算し、内容が空または既存より狭い場合は無条件承認する既存の仕組みを持つため、これを再利用することで新たな hook 実装なしに確認プロンプトを回避できる。

根拠: `commands/work.md:9-23`, `hooks/lib/session-id.sh`

## 統合ポイント

- report issue: `commands/report-review.md`
- issue 起点または docs 変更あり: `commands/task.md`
- issue なし、docs 変更なし: `commands/patch.md`
- 調査起点: `docs/.ai/repo.profile.json` の `primary_docs`

## 注意事項・既知の制限

- report routing はユーザーが issue 番号を明示した新規作業で適用される。
- `/work` 自体の workspace gate は report 判定より先に実行される。

## 変更履歴（git log より自動生成）

- 1e3b7fa fix(#227): avoid rm -f confirmation prompt in /work G-0 by clearing session-approved via Write tool
- db6d6c3 fix(#210): resolve session id from env instead of a shared pointer file
- 0297a81 feat(#126): add report review workflow
- 028b3af fix(#136): announce session-approved path from hook so Claude can locate it
- 13dbefd refactor: reduce duplicate file reads across work/task/patch/codex-review flows
- dd29feb feat(#129): store session approvals per session
- ab4370b fix(#119): explicitly skip Step 3 and jump to Phase 2 on resume
- 26036e6 fix(#119): reset session-approved at G-0 and route resume to Step 2
- 83374dc feat(#108): add session-based approval to eliminate double-confirmation prompts
- 8f2a5fc refactor: update work routing to prioritize issue-based work over docs check
- ef074ee refactor: replace G-0 branch deletion with git checkout main

根拠: `commands/work.md:7-68`
