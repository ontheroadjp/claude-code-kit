# `commands/analyze-access.md` specification

## 目的・役割

`logs/access/*.log`（`hooks/log-access-stop.sh` が記録するアクセスログ）を集計し、KPIダッシュボードと、KPIごとの所見・改善提案（Key Findings & Proposals）を提示する read-only workflow。目的は同一セッション内の重複読み込み（ロス）をゼロに近づけるためのチューニング材料の提供。通常 `/work` から呼ばれる。

根拠: `commands/analyze-access.md:1-11`

## 動作の概要

5 Step で構成される:

```
Step 0: ARGUMENTS から対象月（YYYY-MM / all / 省略=最新月）を解釈
Step 1: scripts/analyze_access.py を実行し JSON を取得
Step 2: JSON の値を Primary/Supporting KPI と Evidence（裏付けデータ）に分けて整理
Step 3: KPI・Evidence のみを根拠に Key Findings（主要な発見）+ Proposals（改善提案）+ Risks and Unknowns を執筆
Step 4: logs/reports/access/<target>_<timestamp>.html を新規作成（KPIダッシュボードを冒頭に、Findings/Proposals をメインコンテンツに、Facts は Evidence として補助的に配置）
Step 5: 標準出力へレポートパスと KPI・上位の発見/提案を提示
```

根拠: `commands/analyze-access.md:16-90`

## 主要な判定ロジック・フロー

- ログの生データ（数千行になり得る）は直接 Read しない。数値の根拠は `scripts/analyze_access.py` が出力する JSON のみとし、AI 側での再集計・推測を禁止する
- スクリプトが非ゼロ終了した場合（対象月のログが存在しない等）はエラーをそのままユーザーに報告して終了する
- HTML レポートは外部リソース参照なしの単一自己完結ファイルとし、末尾に raw JSON を `<details>` で埋め込んで監査可能にする
- **Primary KPI** は `redundant_access_waste.estimated_waste_ratio_pct`（重複読み込みによる推定ロス率）。**Supporting KPI** は `sessions_with_duplicates_ratio` / `redundant_accesses_total` / `redundant_access_waste.estimated_wasted_tokens` / `estimated_wasted_cost_usd` / `duration_ms_stats.avg_ms` / `duration_ms_stats.p95_ms`（`hooks/log-access-stop.sh` 自体の実行時間）。これら以外の Facts（`months` / `session_count` / `top_duplicate_files` / `top_redundant_sessions` / `duration_ms_stats.sample_count` 等）は Evidence（裏付けデータ）として、KPI・所見の後ろに補助的に配置する
- `top_redundant_sessions` は日時・指示内容・無駄な再読み込み回数・重複ファイル一覧に加え、そのセッションで実際に修正が発生したか（`modified`）を持つ。`modified: false` のセッション（読み直しただけで何も変わっていない＝純粋なロス）は Key Findings で優先的に取り上げる

根拠: `commands/analyze-access.md:16-24`, `commands/analyze-access.md:39-52`, `commands/analyze-access.md:70-83`

## 重要な設計判断とその理由

Facts（決定的な集計）と Key Findings/Proposals（AI の解釈）を明確に分離するのは `commands/report-review.md` と同じパターン。数値の解釈にAIの推測が混ざることを防ぎ、集計ロジック自体は `scripts/analyze_access.py` の pytest で検証可能にすることで、レポートの信頼性を担保する。

以前は Facts（統計テーブル）がレポートの主役で、分析は付け足しだった。目的は「重複読み込みロスをゼロにする」というチューニングであり、統計はそのためのエビデンスに過ぎないため、KPIダッシュボード → Key Findings & Proposals をメインコンテンツとし、Facts は Evidence として補助セクションに格下げした（issue #216）。同時に、目的と無関係な一般的なセッション生産性指標（フェーズ別/ツール別アクセス数、修正頻度上位ファイル、修正ゼロセッション比率）と、`/analyze-token-usage` の守備範囲と重複するだけで重複読み込みと紐付いていなかった汎用トークン集計を Facts から除外し、代わりに重複読み込みが実際にどれだけの損失を生んだかを定量化する `redundant_access_waste` を追加した。

`duration_ms_stats`（hook 自体の処理時間）は issue #216 が確立した「重複読み込みロスの特定に一本化する」方針とは別軸の例外として issue #252 で追加した。これはユーザーの作業内容そのものの指標ではなく、`hooks/log-access-stop.sh` というログ記録パイプライン自体のオーバーヘッドを示す運用診断指標であり、`/analyze-auto-approve` が既に同じ枠組みで持っていた指標を揃えたもの。issue #216 が除外した「一般的な生産性指標」の再導入ではない、という区別を明示するため Step 3 でも「重複読み込みロス」の Key Findings とは独立した言及として扱う。

生ログを直接読ませない設計は、`logs/access/*.log` が数千行規模になり得るため、context 消費とトークンコストを抑える目的もある。

## 統合ポイント

- 呼び出し元: `commands/work.md`（ルーティング判定後、または直接呼び出し）
- 呼び出すもの: `scripts/analyze_access.py`
- Codex wrapper: `skills/analyze-access/SKILL.md`
- 出力先: `logs/reports/access/`（`logs/` は `.gitignore` 対象）

## 注意事項・既知の制限

- 唯一の書き込みは `logs/reports/access/` 配下の新規 HTML ファイルのみ。既存ファイルの編集・削除、Git/GitHub の変更は行わない
- レポートファイルは `.gitignore` 対象のため PR には含まれない

## 変更履歴（git log より自動生成）

- 594905d feat(#216): redesign /analyze-* reports around KPI dashboards and findings
- 8d0793a feat(#214): track per-session redundant file reads in /analyze-access
- d7a7627 feat(#212): add /analyze-access, /analyze-auto-approve, /analyze-token-usage log analysis commands
