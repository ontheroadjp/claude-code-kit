# hooks/lib/hook-timing.sh specification

## 目的・役割

`hooks/lib/hook-timing.sh` は、hookが自分自身の実行時間（ミリ秒）を計測するための共有ヘルパーである。`hooks/log-token-usage.sh` と `hooks/log-access-stop.sh` がそれぞれの Stop hook 実行時間を `duration_ms` としてログへ記録するために使う。

根拠: `hooks/lib/hook-timing.sh:1-4`

## 動作の概要

`hook_duration_ms <start>` が唯一の公開関数である。`<start>` は呼び出し側スクリプトの冒頭（payload 処理より前）で取得した `$EPOCHREALTIME` の値を渡す。

- `<start>` が空文字列の場合（`$EPOCHREALTIME` 非対応の bash < 5.0）は `"NA"` を返す
- それ以外は、呼び出し時点の `$EPOCHREALTIME` との差分を純粋な bash 整数演算（`10#` prefix で usec の leading zero を octal 誤解釈しないようにする）でミリ秒に変換して返す

根拠: `hooks/lib/hook-timing.sh:11-29`

## 重要な設計判断とその理由

このロジックは `hooks/auto-approve-readonly.sh` の `_hook_duration_ms`（issue #219 で追加）と同一の計算式である。しかし `auto-approve-readonly.sh` はこのファイルを `source` していない — 995行規模の既存テストスイート（`tests/hooks/test-approval-hooks.sh`）を持つ critical path であり、動作実績のあるインライン実装に触れるリスクを避けるため、意図的に無変更のまま残した（issue #252）。新規に duration 計測を追加する2つの hook（`log-token-usage.sh`・`log-access-stop.sh`）だけがこの共有 lib を使う。

`_hook_duration_ms`（`auto-approve-readonly.sh` 側）はグローバル変数 `HOOK_DURATION_MS` に結果を書き込む副作用型の実装だが、こちらは `<start>` を引数に取り結果を `echo` する純粋関数にした。複数の呼び出し元ファイルから安全に `source` できるようにするため、グローバル変数への依存を避けている。

## 統合ポイント

- 呼び出し元: `hooks/log-token-usage.sh`、`hooks/log-access-stop.sh`（いずれも `REPO_DIR` 解決後に `. "${REPO_DIR}/hooks/lib/hook-timing.sh"` で source）
- 呼び出すもの: なし（純粋な bash 組み込み演算のみ。外部コマンド不要）
- 参考実装: `hooks/auto-approve-readonly.sh` の `_hook_duration_ms`（同一ロジックだが非共有）

## 注意事項・既知の制限

- `$EPOCHREALTIME` は bash 5.0+ のビルトイン変数。呼び出し側スクリプトは `HOOK_START_TIME="${EPOCHREALTIME:-}"` を **payload 処理より前**（`payload=$(cat)` 等の前）に置く必要がある。後段に置くと計測対象からその分の処理時間が漏れる
- サブプロセスベースの代替計測（`date +%s%3N` 等）は行わない。`$EPOCHREALTIME` が使えない環境では計測不能を正直に `"NA"` として記録する方針
