# /analyze-token-usage

`logs/token-usage/*.log`（`hooks/log-token-usage.sh` が記録するトークン使用量ログ）を集計し、KPIダッシュボードと、KPIごとの所見・改善提案を提示する read-only workflow です。通常は `/work` から呼ばれます。

目的はトークン消費量を可視化し、無駄を削減してトークン利用を最適化するためのチューニング材料を提供することです。

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

### Step 2: KPI と Facts の整理

JSON の値をそのまま転記する。数値の再計算・推測は行わない。

**Primary KPI**: 平均キャッシュ効率 `avg_cache_ratio`（セッション横断の平均 cache_ratio。目標: 高いほど良い＝再利用が効いている）

**Supporting KPI**:
- 低キャッシュ効率セッション率 `low_cache_sessions_ratio`（目標: 低いほど良い）
- 高トークン密度セッション率 `high_density_sessions_ratio`（目標: 低いほど良い）
- セッションあたり平均コスト `avg_cost_usd_per_session`
- hook 処理時間 `duration_ms_stats.avg_ms` / `duration_ms_stats.p95_ms`（`hooks/log-token-usage.sh` 自体の実行時間。`"NA"`（`$EPOCHREALTIME` 非対応の bash < 5.0）およびフィールド欠損の旧ログ行は `duration_ms_stats.excluded_count` として数値集計から除外される。ターンごとの生ログ行から集計するため、他の累積値指標と異なり dedupe しない）

**裏付けデータ（Evidence）**:
- 対象月（`months`）、セッション数（`session_count`）、総コスト（`total_cost_usd`）、総トークン数（`total_tokens`）
- セッションあたり平均ターン数（`avg_turns_per_session`）
- モデル別内訳（`model_breakdown`）、プロジェクト（cwd）別内訳（`cwd_breakdown`）
- 日別コスト推移（`daily_cost_trend`）
- コスト上位セッション（`top_expensive_sessions`）
- 低キャッシュ効率セッションの詳細（`low_cache_sessions`）、高トークン密度セッションの詳細（`high_density_sessions`）
- hook 処理時間の分布（`duration_ms_stats.sample_count` / `median_ms` / `max_ms`）

### Step 3: 所見の抽出

Facts のみを根拠に、統計そのものではなく「何が改善できるか」を主役として整理する:

- **主要な発見（Key Findings）**: KPI・Evidence から読み取れる重要な所見を優先度順に列挙する。各所見には根拠となる具体的な数値をインラインで引用する（例:「`avg_cache_ratio` が42%と低く、`low_cache_sessions_ratio` も18%…」）。コスト集中度（特定プロジェクト・モデルへの偏り）、日別推移から読み取れる変化にも言及する。`duration_ms_stats.avg_ms` / `p95_ms` を用いて hook 処理時間が有意な水準か（判断基準の例: 数百 ms 未満は無視できる水準、秒単位に近い場合は要注意）を必ず言及する
- 各発見に対応する **Proposal**（改善提案）を最低1つ添える。優先度（高/中/低）・理由・実施した場合の見込み効果を記す（例: 低キャッシュ効率セッションの原因調査、高コストセッションのパターン分析 等）
- **Opinion**（Facts からの推測）は所見に含めてよいが、事実と明確に書き分ける
- **Risks and Unknowns**: サンプル数が少ない・偏りがある等、解釈の限界を別枠でまとめる

### Step 4: HTML レポートの作成

以下のパスに単一の自己完結 HTML ファイルを新規作成する（外部リソース参照禁止。CSS/JS はすべてインライン）:

```
logs/reports/token-usage/<target>_<YYYYMMDD-HHMMSS>.html
```

- `<target>`: 単一月なら `YYYY-MM`、`all` 指定なら `all`
- `<YYYYMMDD-HHMMSS>`: レポート生成時刻（ローカル実行時刻）

HTML構成:

1. タイトルと生成日時、対象月
2. **KPIダッシュボード**（冒頭）: Primary/Supporting KPI を数値表示する。各指標に目標値・望ましい方向（↑/↓）を明記し、レポート内で最も目立つ位置に置く
3. **主要な発見と改善提案**（メインコンテンツ）: Step 3 で整理した所見+提案を優先度順に列挙する
4. **裏付けデータ（Evidence）**: Step 2 の Evidence を表・リストとして整形する。「上記の発見の根拠データ」である旨を明記し、視覚的な主役ではなく参照用の補助セクションとして配置する
5. Risks and Unknowns
6. 末尾に `<details><summary>Raw data (JSON)</summary><pre>...</pre></details>` として Step 1 の JSON 全体を埋め込む（監査用）

### Step 5: 標準出力への提示

作成したレポートファイルの絶対パスと、KPIダッシュボードの数値 + 主要な発見と改善提案の上位数件を標準出力に提示する（統計の羅列ではなく「現状のKPIと何をすべきか」を中心に述べる）。最後に「read-only 集計のため、レポートファイル以外の作成・変更は行っていません」と明記して終了する。
