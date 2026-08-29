# scripts/

Claude Code のステータス表示とトークン使用量確認のためのユーティリティスクリプトを置くディレクトリ。

## ファイル一覧

| ファイル | 用途 |
|---|---|
| `statusline.sh` | Claude Code のステータスライン表示スクリプト |
| `show-token-usage.sh` | ローカルに蓄積したトークン使用ログの集計・表示スクリプト |
| `analyze_access.py` | `logs/access/*.log` を集計し JSON を出力する（`/analyze-access` から呼ばれる） |
| `analyze_auto_approve.py` | `logs/auto-approve/*.log` を集計し JSON を出力する（`/analyze-auto-approve` から呼ばれる） |
| `analyze_token_usage.py` | `logs/token-usage/*.log` を集計し JSON を出力する（`/analyze-token-usage` から呼ばれる） |
| `work-run-events.sh` | 1回の `/work` と delegated worker の semantic event を固定 schema の per-run JSONL に best-effort 記録する |
| `analyze_work_runs.py` | `logs/work-runs/**/*.jsonl` を集計し、run status・elapsed time・issue/session correlation を JSON で出力する |

`work-run-events.sh` は `start`、`attach`、`emit`、`current` を提供する。通常モードは常に fail-open で、テスト専用 `--strict` のみ schema/IO failure を非ゼロで返す。出力 JSONL は自由記述を受け付けず、既存 telemetry とは `agent_session_id` で join する。

```bash
python3 scripts/analyze_work_runs.py logs/work-runs
```
| `lib/analyze_common.py` | 上記3スクリプトが共有する対象月解決・ログファイル列挙・JSON出力の共通処理 |
| `link-worktree-untracked.sh` | `EnterWorktree` が作成した worktree に、元の working tree の untracked/ignored ファイル・ディレクトリを symlink する（`/work-multi` から呼ばれる） |
| `rename-thread.sh` | Claude Code の現在の会話スレッド名を指定されたブランチ名へ更新する（`/task`・`/patch` から呼ばれる） |

## statusline.sh

Claude Code の statusLine として動作する。stdin に JSON（context window・rate limit 情報）を受け取り、
フォーマットして表示する。

表示項目:
- コンテキスト使用率（%）
- 5時間レートリミットの残量
- 7日レートリミットの残量

**セットアップ**: `setup_statusline.sh` を実行する。`scripts/statusline.sh` を `~/.claude/statusline.sh` に symlink し、`~/.claude/settings.json` に `statusLine` 設定を追加する。

```bash
./setup_statusline.sh
```

## show-token-usage.sh

`hooks/log-token-usage.sh` が `~/.claude/token-usage.log` に記録したデータを集計・表示する。

```
Usage: show-token-usage.sh [-n <count>] [-a|--all] [MODE]

Modes:
  (default)  セッション一覧
  --sum      集計合計・平均・コスト
  --model    モデル別コスト内訳
  --cost     日別コストタイムライン
  --project  プロジェクト別コストランキング
  --time     時間帯別使用ヒートマップ
  --anomaly  低キャッシュ・高トークン密度セッションの検出
```

```bash
# 直近 20 件を表示
bash scripts/show-token-usage.sh

# 全件を集計表示
bash scripts/show-token-usage.sh --all --sum
```

## analyze_access.py / analyze_auto_approve.py / analyze_token_usage.py

`logs/access/`, `logs/auto-approve/`, `logs/token-usage/` 配下の月次ログ（`<YYYY-MM>.log`）をそれぞれパースし、集計結果を JSON として標準出力へ出力する。HTML レポートの生成や分析文の作成は行わない — それらは呼び出し元の `/analyze-access`・`/analyze-auto-approve`・`/analyze-token-usage` コマンドが担う。

```
Usage: analyze_<type>.py [--month YYYY-MM | --all]

--month YYYY-MM  指定した月のログのみを対象にする
--all            全月のログを対象に集計する
(省略時)          利用可能な最新月のみを対象にする
```

```bash
# 最新月のみ
python3 scripts/analyze_access.py

# 特定の月
python3 scripts/analyze_auto_approve.py --month 2026-08

# 全月集計
python3 scripts/analyze_token_usage.py --all
```

`analyze_token_usage.py` は `logs/token-usage/*.log` がセッションごとに累積値を毎ターン追記する形式であることを踏まえ、セッションIDごとに最終行（最大値）のみを集計に用いる（`scripts/show-token-usage.sh --sum` 等は行単位で単純合算するため、セッションをまたいだ比較には注意すること）。

## link-worktree-untracked.sh

`git worktree add`（`EnterWorktree` の内部実装）は tracked ファイルのみをチェックアウトするため、`commands/work-multi.md` が新規 worktree に切り替えた直後に、元の working tree の untracked/ignored ファイル・ディレクトリを symlink するために使う。`.git`・`.claude`（`EnterWorktree` 自身が worktree を格納する予約ディレクトリ）は対象から除外する。

```bash
bash scripts/link-worktree-untracked.sh <元の working tree の絶対パス>
```

## rename-thread.sh

Claude Code が管理する現在セッションの transcript に `custom-title` レコードを追記する。`/task` と `/patch` はブランチ切替直後に Git が返すブランチ名を渡して実行する。Claude Code のセッション ID または transcript が見つからない場合は何も変更せず終了するため、Codex CLI を含む非 Claude Code 環境でも安全に呼び出せる。

```bash
bash scripts/rename-thread.sh fix/example
```
