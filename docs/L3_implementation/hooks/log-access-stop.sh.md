# hooks/log-access-stop.sh specification

## 目的・役割

Stop hook。`hooks/log-access-prompt.sh` / `hooks/log-access-tool.sh` が `STATE_FILE`（`/tmp/claude-access-sessions/<session_id>.json`）に蓄積したセッション状態を、`logs/access/*.log` が期待する固定セクション形式のブロックにフォーマットし、`PENDING_FILE` へ書き出す。`scripts/analyze_access.py`（呼び出し元は `commands/analyze-access.md`）がこのログを消費する。

根拠: `hooks/log-access-stop.sh:1-142`

## 動作の概要

1. スクリプト冒頭（`payload=$(cat)` より前）で `$EPOCHREALTIME` を `HOOK_START_TIME` として取得し、`hooks/lib/hook-timing.sh` を source する
2. `STATE_FILE` が存在しない、または `accesses` が空の場合は何もせず終了する（`log-access-prompt.sh` が新規セッションで state を初期化する前提）
3. `[日時]` `[ユーザーからの指示内容]` `[アクセスサマリ]` `[フェーズ別アクセス順序]` `[修正したファイル]` `[トークン使用量]`（transcript がある場合のみ）を state と transcript から組み立てる
4. `hook_duration_ms "$HOOK_START_TIME"` でこの回の実行時間を求め、`STATE_FILE` の `hook_durations_ms` 配列に追記して書き戻す。この配列（このセッションで過去に呼ばれた全 Stop 呼び出しの実行時間）を `[Hook処理時間]` セクションとしてカンマ区切りで出力する
5. 全体を `{ ... } > "$PENDING_FILE"` でまとめて書き出す。`PENDING_FILE` は次の `/work` 開始時（`log-access-prompt.sh`/`log-access-tool.sh` 側）に main log へ flush される

根拠: `hooks/log-access-stop.sh:1-142`

## 主要な判定ロジック・フロー

- `logs/access/*.log` は1セッション1ブロックの形式（ターンごとではない）。一方 `duration_ms` はこの hook の *呼び出しごと*（ターンごと）の実行時間であり、ブロックの粒度と一致しない。この差を埋めるため、単一の最新値ではなく `STATE_FILE.hook_durations_ms` に全呼び出し分を配列として蓄積し、最終的に flush される1ブロックにその全履歴をカンマ区切りで埋め込む設計にした
- `hook_durations_ms` への追記は `state=$(echo "$state" | jq --arg d ... '.hook_durations_ms = ((.hook_durations_ms // []) + [$d])')` の形で行う。`// []` により、この機能追加前に作られた `STATE_FILE`（`hook_durations_ms` フィールドを持たない）でもエラーなく初回追記できる
- `printf '%s' "$state" > "$STATE_FILE"` は `{ ... } > "$PENDING_FILE"` ブロックの**内部**にあるが、個別コマンドのリダイレクトはブロック全体のリダイレクトより優先されるため、この行の出力は `PENDING_FILE` ではなく `STATE_FILE` に書き込まれる
- `[Hook処理時間]` の値に `"NA"`（計測不能）が混在し得る。`scripts/analyze_access.py` 側でパース時に非数値トークンとして除外する

根拠: `hooks/log-access-stop.sh:132-142`

## 重要な設計判断とその理由

以前はこの hook が `STATE_FILE` を書き戻すことはなく、read-only な消費者だった（書き込みは `log-access-prompt.sh`/`log-access-tool.sh` の役割）。`hook_durations_ms` を複数ターンにわたって累積する必要があるため、この hook にも書き戻しの責務を追加した。追記対象は新規フィールドのみで、既存フィールド（`accesses` / `modified_files` 等）は変更しないため、他の2つの hook との競合は発生しない。

`issue #216` で「重複読み込みロスの特定」に一本化する目的から一般的な生産性指標を除外する方針が確立されていたが、hook 自体の処理時間はその重複読み込みという問いとは別軸の「ログ記録パイプライン自体の負荷診断」指標として、issue #252 で明示的に追加した。

## 統合ポイント

- 入力: `STATE_FILE`（`hooks/log-access-prompt.sh`/`hooks/log-access-tool.sh` が更新）、transcript（`payload.transcript_path`）
- 出力: `PENDING_FILE`（`hooks/log-access-prompt.sh`/`hooks/log-access-tool.sh` が main log へ flush）
- 依存: `hooks/lib/hook-timing.sh`（`hook_duration_ms` を source して使用）
- 消費者: `scripts/analyze_access.py`（`commands/analyze-access.md` 経由）
- 登録: `install.sh` が `hooks/*.sh` を `~/.claude/hooks/` / `~/.codex/hooks/` へ symlink し、Stop イベントとして登録する

## 注意事項・既知の制限

- `$EPOCHREALTIME` 非対応の bash（5.0未満）では該当呼び出し分が `"NA"` として `hook_durations_ms` に記録され、`scripts/analyze_access.py` 側の数値集計から除外される
- `hook_durations_ms` はセッションが `PENDING_FILE` として flush されるまで無制限に増え続ける。通常のセッション長（数十〜百数十ターン程度）では実用上問題にならない想定だが、上限は設けていない
- `set -euo pipefail` を宣言している（issue #267。以前は宣言しておらず `hooks/log-token-usage.sh` と規約が揺れていた）。`{ ... } > "$PENDING_FILE"` ブロック内で失敗すると `PENDING_FILE` が部分的に書き込まれた状態で終了し得るが、ブロック開始前（`accesses_count`/`duplicates`/`phases` 算出）で使う jq クエリは同じ `$state` に対する決定的なクエリであり、そこを通過できる状態であればブロック内で失敗する可能性は実用上低いと判断した

## 変更履歴（git log より自動生成）

- a565c97 feat(#252): add hook execution-time aggregation to /analyze-* commands
- deb5360 feat(#83): add token usage summary to access log for redundant-access detection
- 761866d fix(#81): accumulate access log state across turns per /work session
- 5b554ea fix: resolve symlink in BASH_SOURCE and move state init to UserPromptSubmit
- 381715b feat(#69): consolidate hook log outputs under logs/ directory
- fca17ed feat(#67): track file access order and duplicates in access log hooks
- 3251527 feat(#48): extend phase tracking to docs-sync and init-docs commands
- c66082e feat(#48): add hooks to log file access per phase during work/task/patch execution
