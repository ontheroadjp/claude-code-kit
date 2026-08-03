# /analyze-auto-approve

`logs/auto-approve/*.log`（`hooks/auto-approve-readonly.sh` が記録する PreToolUse 判定ログ）を集計し、KPIダッシュボードと、KPIごとの所見・改善提案を提示する read-only workflow です。通常は `/work` から呼ばれます。

目的はどのタイミングで自動承認され、どのタイミングでユーザー判断（承認プロンプト）になったかを可視化し、安全性を保ちながら自動承認率を100%に近づけるためのチューニング材料を提供することです。

## 境界

- 集計は `scripts/analyze_auto_approve.py`（Python）が行う。ログの生データを直接 Read しない — 大量行を context に読み込まず、スクリプトが出力する JSON のみを Facts の根拠とする
- リポジトリの既存ファイルの編集・削除は行わない
- Git・GitHub の状態（commit・push・issue・PR）は変更しない
- hook 自体（`hooks/auto-approve-readonly.sh` 等）の変更は行わない — 改善提案は Proposals として提示するに留める
- 唯一の書き込みは `logs/reports/auto-approve/` 配下への新規 HTML レポートファイルの作成のみ（`logs/` は `.gitignore` 対象のため commit されない）

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
python3 scripts/analyze_auto_approve.py <opt>
```

- 標準出力の JSON をそのまま Facts の根拠として保持する
- コマンドがゼロ以外で終了した場合（対象月のログが存在しない等）は、エラーメッセージをそのままユーザーに報告して終了する

### Step 2: KPI と Facts の整理

JSON の値をそのまま転記する。数値の再計算・推測は行わない。

**Primary KPI**:
- 全体の自動承認率 `result_ratio_pct.approved`（目標: 100%に近づける）
- 定型処理（`/work` パイプラインの git/gh write系操作）のユーザー確認率 `routine_ops.result_ratio_pct.user_prompt`（目標: 0%に近づける＝定型処理は100%自動承認）

**Supporting KPI**:
- 全体の user_prompt 率 / blocked 率（`result_ratio_pct.user_prompt` / `result_ratio_pct.blocked`）
- 月別推移 `monthly_trend`（過去のチューニングが効いているかの時系列判断）
- `routine_ops.patterns_needing_approval`（user_prompt に落ちている定型処理パターンの上位リスト。各要素はパターン名・user_prompt件数・approved件数・blocked件数を持つ。`routine_ops` は `hooks/auto-approve-readonly.sh` の `check_session_approved()` が認識する git/gh write系コマンド形状で分類したもの）

**裏付けデータ（Evidence）**:
- 対象月（`months`）、総判定数（`total_decisions`）
- tool 別内訳（`tool_counts`）、agent 別内訳（`agent_counts`）
- 判定数上位セッション（`top_sessions`）
- blocked パターン上位（`top_blocked_patterns`）、user_prompt パターン上位（`top_user_prompt_patterns`）
- 直近の blocked / user_prompt サンプル（`recent_blocked_samples` / `recent_user_prompt_samples`）

### Step 3: 所見の抽出

Facts のみを根拠に、統計そのものではなく「何が改善できるか」を主役として整理する:

- **主要な発見（Key Findings）**: KPI・Evidence から読み取れる重要な所見を優先度順に列挙する。各所見には根拠となる具体的な数値をインラインで引用する（例:「`routine_ops.result_ratio_pct.user_prompt` が34%、うち `git commit` パターンが最多で…」）。`monthly_trend` から自動承認率が改善傾向か悪化傾向かを必ず言及する
- 各発見に対応する **Proposal**（改善提案）を最低1つ添える。特に `routine_ops.patterns_needing_approval` の上位パターンについては、そのパターンが現状なぜ user_prompt に落ちているか（例: セッション内でまだ `tool:git_write` 等が承認されていない、または `is_safe_segment()` の一般 allowlist に含まれていない）と、恒久的に自動承認へ追加する場合の具体的な提案（対象パターン・想定される安全性の根拠）をセットで記述する。優先度（高/中/低）・理由を付ける
- **Opinion**（Facts からの推測）は所見に含めてよいが、事実と明確に書き分ける
- **Risks and Unknowns**: サンプル数が少ない・偏りがある等、解釈の限界を別枠でまとめる

### Step 4: HTML レポートの作成

以下のパスに単一の自己完結 HTML ファイルを新規作成する（外部リソース参照禁止。CSS/JS はすべてインライン）:

```
logs/reports/auto-approve/<target>_<YYYYMMDD-HHMMSS>.html
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
