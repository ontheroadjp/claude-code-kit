# /analyze-access

`logs/access/*.log`（`hooks/log-access-stop.sh` が記録するアクセスログ）を集計し、KPIダッシュボードと、KPIごとの所見・改善提案を提示する read-only workflow です。通常は `/work` から呼ばれます。

目的は同一セッション内での同一ファイルの重複読み込み（ロス）を可視化し、それをゼロに近づけるためのチューニング材料を提供することです。

## 境界

- 集計は `scripts/analyze_access.py`（Python）が行う。ログの生データを直接 Read しない — 大量行を context に読み込まず、スクリプトが出力する JSON のみを Facts の根拠とする
- リポジトリの既存ファイルの編集・削除は行わない
- Git・GitHub の状態（commit・push・issue・PR）は変更しない
- 唯一の書き込みは `logs/reports/access/` 配下への新規 HTML レポートファイルの作成のみ（`logs/` は `.gitignore` 対象のため commit されない）

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
python3 scripts/analyze_access.py <opt>
```

- 標準出力の JSON をそのまま Facts の根拠として保持する
- コマンドがゼロ以外で終了した場合（対象月のログが存在しない等）は、エラーメッセージをそのままユーザーに報告して終了する

### Step 2: KPI と Facts の整理

JSON の値をそのまま転記する。数値の再計算・推測は行わない。

**Primary KPI**: 重複読み込みによる推定ロス率 `redundant_access_waste.estimated_waste_ratio_pct`（総トークンに占める、重複読み込みで無駄になった推定割合。目標: 0%に近づける）

**Supporting KPI**:
- 重複発生セッション率 `sessions_with_duplicates_ratio`
- 総無駄読み込み回数 `redundant_accesses_total`
- 推定損失トークン `redundant_access_waste.estimated_wasted_tokens` / 推定損失コスト `redundant_access_waste.estimated_wasted_cost_usd`
- hook 処理時間 `duration_ms_stats.avg_ms` / `duration_ms_stats.p95_ms`（`hooks/log-access-stop.sh` 自体の実行時間。重複読み込みロスとは別軸の、ログ記録パイプライン自体の負荷診断指標。`"NA"`（`$EPOCHREALTIME` 非対応の bash < 5.0）は `duration_ms_stats.excluded_count` として数値集計から除外される）

**裏付けデータ（Evidence）**:
- 対象月（`months`）、セッション数（`session_count`）、総アクセス数、セッションあたり平均アクセス数
- 重複アクセス上位ファイル（`top_duplicate_files`、全セッション横断の合算。各エントリは発生元 phase/command 別の内訳 `by_phase` を持つ）
- 無駄な再読み込みが多いセッション上位（`top_redundant_sessions`。各要素は日時・指示内容・無駄な再読み込み回数・重複ファイル一覧・そのセッションで実際にファイルを修正したか（`modified`）を持つ）
- hook 処理時間の分布（`duration_ms_stats.sample_count` / `median_ms` / `max_ms`）

### Step 3: 所見の抽出

Facts のみを根拠に、統計そのものではなく「何が改善できるか」を主役として整理する:

- **主要な発見（Key Findings）**: KPI・Evidence から読み取れる重要な所見を優先度順に列挙する。各所見には根拠となる具体的な数値をインラインで引用する（例:「`estimated_waste_ratio_pct` が12%、うち `/path/to/file` への重複が最多で…」）。`top_redundant_sessions` のうち `modified: false`（変更につながらなかった＝純粋なロス）のセッションは優先的に取り上げる。`duration_ms_stats.avg_ms` / `p95_ms` を用いて hook 処理時間が有意な水準か（判断基準の例: 数百 ms 未満は無視できる水準、秒単位に近い場合は要注意）を必ず言及する
- `top_duplicate_files` の上位エントリごとに `by_phase`（phase/command 別内訳）を用いて重複クラスタの主因を明示的に特定し所見に含める（例:「`hooks/auto-approve-readonly.sh` への重複は work phase が72%（38/53回）を占め、/work の investigation phase が主因」）。単一 phase に偏っていない場合は「複数 phase にまたがる」旨を明記する。これは所見の一部として毎回必須（issue #308）
- 各発見に対応する **Proposal**（改善提案）を最低1つ添える。優先度（高/中/低）・理由・実施した場合の見込み効果を記す（例: 頻出アクセスファイルを `docs/.ai/repo.profile.json` の investigation 起点に加える 等）
- **Opinion**（Facts からの推測）は所見に含めてよいが、事実と明確に書き分ける
- **Risks and Unknowns**: サンプル数が少ない・偏りがある等、解釈の限界を別枠でまとめる

### Step 4: HTML レポートの作成

以下のパスに単一の自己完結 HTML ファイルを新規作成する（外部リソース参照禁止。CSS/JS はすべてインライン）:

```
logs/reports/access/<target>_<YYYYMMDD-HHMMSS>.html
```

- `<target>`: 単一月なら `YYYY-MM`、`all` 指定なら `all`
- `<YYYYMMDD-HHMMSS>`: レポート生成時刻（ローカル実行時刻）

HTML構成:

1. タイトルと生成日時、対象月
2. **KPIダッシュボード**（冒頭）: Primary/Supporting KPI を数値表示する。各指標に目標値・望ましい方向（↑/↓）を明記し、レポート内で最も目立つ位置に置く
3. **主要な発見と改善提案**（メインコンテンツ）: Step 3 で整理した所見+提案を優先度順に列挙する
4. **裏付けデータ（Evidence）**: Step 2 の Evidence を表・リストとして整形する。「上記の発見の根拠データ」である旨を明記し、視覚的な主役ではなく参照用の補助セクションとして配置する。`top_redundant_sessions` は「日時・指示内容・無駄な再読み込み回数・重複ファイル（ファイル名 + 回数）・修正の有無」を1行とする表で表示する
5. Risks and Unknowns
6. 末尾に `<details><summary>Raw data (JSON)</summary><pre>...</pre></details>` として Step 1 の JSON 全体を埋め込む（監査用）

### Step 5: 標準出力への提示

作成したレポートファイルの絶対パスと、KPIダッシュボードの数値 + 主要な発見と改善提案の上位数件を標準出力に提示する（統計の羅列ではなく「現状のKPIと何をすべきか」を中心に述べる）。最後に「read-only 集計のため、レポートファイル以外の作成・変更は行っていません」と明記して終了する。
