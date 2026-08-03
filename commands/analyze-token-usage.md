# /analyze-token-usage

`logs/token-usage/*.log`（`hooks/log-token-usage.sh` が記録するトークン使用量ログ）を集計し、Facts と AI による分析を分離したレポートを提示する read-only workflow です。通常は `/work` から呼ばれます。

## 境界

- 集計は `scripts/analyze_token_usage.py`（Python）が行う。ログの生データを直接 Read しない — 大量行を context に読み込まず、スクリプトが出力する JSON のみを Facts の根拠とする
- リポジトリの既存ファイルの編集・削除は行わない
- Git・GitHub の状態（commit・push・issue・PR）は変更しない
- 唯一の書き込みは `logs/reports/token-usage/` 配下への新規 HTML レポートファイルの作成のみ（`logs/` は `.gitignore` 対象のため commit されない）

---

## ワークフロー

### Step 0: 対象月の解釈

ARGUMENTS を以下のルールで解釈する:

- 空: 対象月を指定しない（スクリプト側で最新月を自動選択）
- `YYYY-MM`: その月を対象にする
- `all`: 全月を対象にする
- 上記以外: ユーザーに正しい形式（`YYYY-MM` または `all`）を尋ねて待機する

### Step 1: 集計スクリプトの実行

リポジトリルートで以下を実行する（`<opt>` は Step 0 の解釈結果に応じて省略 / `--month YYYY-MM` / `--all` のいずれか）:

```bash
python3 scripts/analyze_token_usage.py <opt>
```

- 標準出力の JSON をそのまま Facts の根拠として保持する
- コマンドがゼロ以外で終了した場合（対象月のログが存在しない等）は、エラーメッセージをそのままユーザーに報告して終了する

**注**: `logs/token-usage/*.log` はセッションごとに Stop イベントのたびに**その時点までの累積値**が追記される形式である。このスクリプトはセッションIDごとに最終行（最大値）のみを集計に用いる（`raw_line_count` が生の行数、`session_count` が重複排除後のセッション数）。全行を単純合算すると水増しになるため、この重複排除を経ていない集計値と比較しないこと。

### Step 2: Facts の整理

JSON の値をそのまま転記する。数値の再計算・推測は行わない:

- 対象月（`months`）、セッション数（`session_count`）、総コスト（`total_cost_usd`）、総トークン数（`total_tokens`）
- セッションあたり平均コスト・平均ターン数
- モデル別内訳（`model_breakdown`）、プロジェクト（cwd）別内訳（`cwd_breakdown`）
- 日別コスト推移（`daily_cost_trend`）
- コスト上位セッション（`top_expensive_sessions`）
- 低キャッシュ効率セッション（`low_cache_sessions`）、高トークン密度セッション（`high_density_sessions`）

### Step 3: 分析

Facts のみを根拠に、以下を分離して整理する:

- **Assessment**: コスト集中度（特定プロジェクト・モデルへの偏り）、キャッシュ効率の傾向、日別推移から読み取れる変化
- **Opinions**: Facts から導いた見解。事実と混同しない
- **Proposals**: 改善候補（例: 低キャッシュ効率セッションの原因調査、高コストセッションのパターン分析 等）。優先度と理由を付ける
- **Risks and Unknowns**: サンプル数が少ない・偏りがある等、解釈の限界

### Step 4: HTML レポートの作成

以下のパスに単一の自己完結 HTML ファイルを新規作成する（外部リソース参照禁止。CSS/JS はすべてインライン）:

```
logs/reports/token-usage/<target>_<YYYYMMDD-HHMMSS>.html
```

- `<target>`: 単一月なら `YYYY-MM`、`all` 指定なら `all`
- `<YYYYMMDD-HHMMSS>`: レポート生成時刻（ローカル実行時刻）

HTML構成:

1. タイトルと生成日時、対象月
2. Facts（JSON の値を表・リストとして整形。数値は JSON の値をそのまま使う）
3. Assessment / Opinions / Proposals / Risks and Unknowns（Step 3 の内容）
4. 末尾に `<details><summary>Raw data (JSON)</summary><pre>...</pre></details>` として Step 1 の JSON 全体を埋め込む（監査用）

### Step 5: 標準出力への提示

作成したレポートファイルの絶対パスと、Step 3 の要約（Summary 数文 + Proposals 上位数件）を標準出力に提示する。最後に「read-only 集計のため、レポートファイル以外の作成・変更は行っていません」と明記して終了する。
