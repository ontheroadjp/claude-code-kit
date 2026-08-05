# `commands/analyze-token-usage.md` specification

## 目的・役割

`logs/token-usage/*.log`（`hooks/log-token-usage.sh` が記録するトークン使用量ログ）を集計し、KPIダッシュボードと、KPIごとの所見・改善提案（Key Findings & Proposals）を提示する read-only workflow。目的はトークン利用の無駄を削減し最適化するためのチューニング材料の提供。通常 `/work` から呼ばれる。

根拠: `commands/analyze-token-usage.md:1-11`

## 動作の概要

5 Step で構成される:

```
Step 0: ARGUMENTS から対象月（YYYY-MM / all / 省略=最新月）を解釈
Step 1: scripts/analyze_token_usage.py を実行し JSON を取得
Step 2: JSON の値を Primary/Supporting KPI と Evidence（裏付けデータ）に分けて整理
Step 3: KPI・Evidence のみを根拠に Key Findings（主要な発見）+ Proposals（改善提案）+ Risks and Unknowns を執筆
Step 4: logs/reports/token-usage/<target>_<timestamp>.html を新規作成（KPIダッシュボードを冒頭に、Findings/Proposals をメインコンテンツに、Facts は Evidence として補助的に配置）
Step 5: 標準出力へレポートパスと KPI・上位の発見/提案を提示
```

根拠: `commands/analyze-token-usage.md:14-79`

## 主要な判定ロジック・フロー

- `logs/token-usage/*.log` はセッションごとに Stop イベントのたびに**その時点までの累積値**が追記される形式である。`scripts/analyze_token_usage.py` がセッションIDごとに最終行のみを集計に用いるため、この command は生ログを直接読まず、スクリプトの重複排除後の JSON のみを根拠とする
- スクリプトの出力には `raw_line_count`（生の行数）と `session_count`（重複排除後）の両方が含まれ、両者を混同しないことを Step 1 で明示する
- **Primary KPI** は `avg_cache_ratio`（セッション横断のキャッシュ効率平均。高いほど良い）。**Supporting KPI** は `low_cache_sessions_ratio` / `high_density_sessions_ratio`（いずれも低いほど良い）、`avg_cost_usd_per_session`、`duration_ms_stats.avg_ms` / `duration_ms_stats.p95_ms`（`hooks/log-token-usage.sh` 自体の実行時間）

根拠: `commands/analyze-token-usage.md:16-29`, `commands/analyze-token-usage.md:33-46`

## 重要な設計判断とその理由

累積値ログをそのまま合算すると同一セッションの値を毎ターン重複計上してしまう（既存の `scripts/show-token-usage.sh --sum` はこの重複排除を行っていない）。この command 系列では正しい月次コストを示すため、セッションIDごとの最終値のみを合算する方式を採用した。

以前は Facts（統計テーブル）がレポートの主役で、分析は付け足しだった。目的は「トークン利用を最適化する」というチューニングであり、統計はそのためのエビデンスに過ぎないため、KPIダッシュボード → Key Findings & Proposals をメインコンテンツとし、Facts は Evidence として補助セクションに格下げした（issue #216）。3コマンド（`/analyze-access` / `/analyze-auto-approve` / `/analyze-token-usage`）で同一のレポート構成（KPIダッシュボード → Key Findings & Proposals → Evidence → Risks and Unknowns）に統一している。

`duration_ms_stats` は `/analyze-auto-approve` が既に持つ「hook 自体の実行時間が体感レイテンシに寄与しているか」という診断軸を、`hooks/log-token-usage.sh` にも揃えるために追加した（issue #252）。ただし `duration_ms` はコスト・トークンと違い累積値ではなく Stop hook 呼び出し単位の値であるため、`scripts/analyze_token_usage.py` 側の集計はセッション単位に重複排除する前の生ログ行を対象にする（詳細は `docs/L3_implementation/scripts/analyze_token_usage.py.md`）。

## 統合ポイント

- 呼び出し元: `commands/work.md`
- 呼び出すもの: `scripts/analyze_token_usage.py`
- Codex wrapper: `skills/analyze-token-usage/SKILL.md`
- 出力先: `logs/reports/token-usage/`（`logs/` は `.gitignore` 対象）
- 関連する既存ツール: `scripts/show-token-usage.sh`（集計方式が異なる点に注意）

## 注意事項・既知の制限

- 唯一の書き込みは `logs/reports/token-usage/` 配下の新規 HTML ファイルのみ
- `scripts/show-token-usage.sh` は `~/.claude/token-usage.log`（レガシーパス）を読む一方、`hooks/log-token-usage.sh` の現在の書き込み先は `logs/token-usage/<YYYY-MM>.log` であり、両者は異なるログを参照している

## 変更履歴（git log より自動生成）

- 594905d feat(#216): redesign /analyze-* reports around KPI dashboards and findings
- d7a7627 feat(#212): add /analyze-access, /analyze-auto-approve, /analyze-token-usage log analysis commands
