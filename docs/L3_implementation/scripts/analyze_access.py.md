# `scripts/analyze_access.py` specification

## 目的・役割

`logs/access/*.log`（`hooks/log-access-stop.sh` が記録するセッション単位のアクセスログ）をパースし、集計結果を JSON として標準出力へ出力する。HTML生成・分析文の作成は行わない（`commands/analyze-access.md` が担う）。

根拠: `scripts/analyze_access.py:1-6`

## 動作の概要

1. ログはセッション毎に `---` のみの行で区切られたブロック形式で、各ブロックは `[日時]` / `[ユーザーからの指示内容]` / `[アクセスサマリ]` / `[フェーズ別アクセス順序]` / `[修正したファイル]` / `[トークン使用量]` / `[Hook処理時間]` の固定セクションヘッダを持つ（`[トークン使用量]` は transcript が無い場合、`[Hook処理時間]` はこの機能追加前に flush されたセッションの場合に省略される）
2. `split_blocks()` でブロックに分割し、`split_sections()` で各ブロックをセクション名 → 本文の辞書に変換する
3. セクションごとに正規表現でパースする: `parse_summary()`（総アクセス数・絞り込み読み数（`narrowed_total`。issue #363）・重複ファイル。各重複エントリは `parse_phase_breakdown()` で `[phase:count, ...]` サフィックスをパースした `by_phase` と、`(narrowed:N)` サフィックスをパースした `narrowed_count` を持つ。サフィックスが無い旧フォーマットの行は `by_phase == {}` / `narrowed_count == 0`、issue #308 / #363）、`parse_modified_files()`、`parse_token_usage()`、`parse_hook_durations()`（`hooks/log-access-stop.sh` 自体の実行時間。カンマ区切りの生トークンを文字列リストのまま返し、"NA" 等の非数値判定は集計側に委ねる）。`[フェーズ別アクセス順序]` セクションは既存のセクション境界検出（`SECTION_HEADERS`）には残すが、内容はパースしない（本スクリプトの集計対象外。phase の内訳は `[アクセスサマリ]` の `by_phase` サフィックス経由で取得する）
4. `load_sessions(months)` で対象月の全ログファイルを読み、セッションのリストを作る
5. `aggregate(months, sessions)` でセッション横断の集計を行う: 重複ファイルの上位N件（phase別・narrowed件数の内訳付き）、セッション単位の無駄な再読み込み集計、`redundant_access_waste()` による損失推定、`duration_ms_stats()` による hook 処理時間の分布集計、および全セッション合算の絞り込み読み率 `narrowed_read_ratio_pct`（issue #363）
6. `main()` で `lib.analyze_common` の共通CLI・月解決処理を呼び、結果を JSON として出力する

`session["duplicates"]` は `hooks/log-access-stop.sh` 側で `group_by(.path)` によりセッション単位で既に重複検出済みのリストであり、各エントリは `path` / `count`（全 phase 横断の合計、後方互換で不変） / `by_phase`（phase別内訳）を持つ。この性質を利用し、`aggregate()` は各セッションの `duplicates` から「同一セッション内で同じファイルを何度も読んで無駄になった回数」（`count - 1` の合計）を `redundant_accesses_total` として集計し、`top_redundant_sessions()` で無駄な再読み込みが多いセッション上位（日時・指示内容・無駄な再読み込み回数・重複ファイル一覧・`modified`）を抽出する。`modified` は `session["modified_files"]` が非空かどうかの真偽値で、「読み直しただけで実際には何も変更しなかった」セッションを一目で判別できるようにするためのフィールドである。既存の `top_duplicate_files`（全セッション横断で重複カウントを単純合算したもの）はセッション横断の傾向把握用として残す。`aggregate()` は `duplicate_phase_totals`（path → phase → count のセッション横断合算）も並行して蓄積し、`top_n()` がこれを各エントリの `by_phase` として付与する（issue #308）。同様に `duplicate_narrowed_totals`（path → narrowed_count のセッション横断合算）も蓄積し、`top_n()` の各エントリに `narrowed_count` として付与する（issue #363）。`aggregate()` はセッション横断の `narrowed_accesses_total`（各セッションの `narrowed_accesses` の合計）も集計し、`total_accesses` に対する比率を `narrowed_read_ratio_pct` として返す。

`redundant_access_waste()` は、`duplicates` と `token_usage` の両方を持つセッションについて「セッション内の1アクセスあたりの平均トークン/コスト（`token_usage.total または cost_usd` ÷ `total_accesses`）」を近似単価とし、これに無駄な再読み込み回数を掛けて損失トークン数・損失コストを推定する。この関数だけが `duplicates`（頻度）と実際の損失（インパクト）を直接結びつける — 他の Fact はすべて頻度のみを報告する。

`duration_ms_stats()` は全セッションの `hook_durations_ms`（各セッション内での `hooks/log-access-stop.sh` 呼び出しごとの実行時間）をフラットに1つのリストへプールし、`"NA"` や非数値トークンを除外した上で `sample_count` / `excluded_count` / `avg_ms` / `median_ms` / `p95_ms`（`lib.analyze_common.percentile()` を使用） / `max_ms` を計算する。他の Fact がセッション単位（1セッション=1値）で集計されるのに対し、これは呼び出し単位（1セッションに複数値がありうる）でプールする点が異なる。`(tool, detail)` のような分類軸を持たないため、`scripts/analyze_auto_approve.py` の `duration_ms_stats` と異なり `top_slow_patterns` は持たない。

根拠: `scripts/analyze_access.py:93-148`, `scripts/analyze_access.py:180-215`, `scripts/analyze_access.py:284-328`, issue #308, issue #363

## 主要な判定ロジック・フロー

- ブロック区切りは正規表現 `^---$`（複数行モード）による厳密一致とし、ユーザー指示文中に偶然 `---` という語が単独行で現れないことを前提とする
- セクション本文の抽出は既知の6ヘッダのみを対象にした `SECTION_RE` で行い、`[フェーズ別アクセス順序]` セクション内部に現れる `[work] N件` のようなネストした角括弧はセクション境界として誤認しない（`SECTION_RE` に含まれないヘッダ名のため）
- ファイルは `errors="replace"` で読み込み、過去のログ破損（マルチバイト文字の途中切断。issue #194 で修正済みの旧バグに起因）があっても解析全体を失敗させない
- `DUPLICATE_RE` の `[phase:count, ...]` サフィックスは非キャプチャの optional group（`(?:\s*\[(.+?)\])?`）としており、サフィックスが無い行（issue #308 以前に flush されたログ）でも `findall()` は空文字列を返すだけで例外にならない。`parse_phase_breakdown("")` は `{}` を返すため、後方互換が保たれる
- `DUPLICATE_RE` の末尾には `(narrowed:N)` 用の同様の optional group（`(?:\s*\(narrowed:(\d+)\))?`）も追加した（issue #363）。`TOTAL_ACCESSES_RE` も同じパターンで `(絞り込み読み: N)` を optional group として追加している。両方とも、サフィックスが無い行では `None`/空文字列として扱われ `parse_summary()` 側で `0` にフォールバックする

根拠: `scripts/analyze_access.py:39-47`, `scripts/analyze_access.py:100-113`

## 重要な設計判断とその理由

Facts の再現性を担保するため、集計はすべて決定的な正規表現パースで行い、AI による要約や推測を混在させない。`commands/analyze-access.md` 側はこの JSON のみを根拠として Key Findings / Proposals を執筆する設計になっている。

`/analyze-access` の目的は「同一セッション内の重複読み込みロスの特定」に一本化されているため、この目的と直接関係しないセッション横断の一般的な生産性指標（フェーズ別/ツール別アクセス数、修正頻度上位ファイル、修正ゼロセッション比率）、および `/analyze-token-usage` の守備範囲と重複するセッション横断の汎用トークン集計は、集計対象から外している（issue #216）。目的外の指標を混在させると、レポートが「重複読み込みのロス」という単一の問いに答えられなくなるため。

`duration_ms_stats`（hook 自体の処理時間）は issue #216 以降に追加した唯一の例外である（issue #252）。これは「重複読み込みロス」という問いには答えないが、issue #216 が除外した「一般的なセッション生産性指標」とも異なる — ユーザーの作業内容そのものではなく、ログ記録パイプライン（`hooks/log-access-stop.sh`）自体のオーバーヘッドを測る運用診断指標であり、`/analyze-auto-approve` が既に同じ枠組みで `duration_ms_stats` を持っていたことと整合させるために別軸の指標として追加した。

`narrowed_read_ratio_pct` / `narrowed_count`（issue #363）も同様に issue #216 の除外方針の例外として追加した。単なる「絞り込み読みの実施率」という汎用生産性指標ではなく、`redundant_access_waste` が答える「重複読み込みロス」という問いを補強する指標として位置付けている: 同じ重複読み込みでも、絞り込み読み（`offset`/`limit` 使用）の再読みは全文再読みよりコストが低いため、`top_duplicate_files`/`top_redundant_sessions` の `narrowed_count` を見れば「この重複は本当に無駄が大きいのか（全文再読みが多い）、それとも軽微なのか（対象読みが多い）」を判別できる。`redundant_access_waste()` 自体の損失推定ロジック（セッション平均コストで按分する近似）は変更していない — narrowed 情報の追加は Evidence の粒度を上げるものであり、既存の推定式には反映していない。

## 統合ポイント

- 入力: `logs/access/<YYYY-MM>.log`（`hooks/log-access-stop.sh` が生成）
- 共通処理: `scripts/lib/analyze_common.py`（`percentile()` を含む）
- 呼び出し元: `commands/analyze-access.md`
- テスト: `tests/scripts/test_analyze_access.py`

## 注意事項・既知の制限

- `[修正したファイル]` セクションが空（変更なし）の場合、`parse_modified_files()` は空リストを返す
- `top_duplicate_files` / `top_redundant_sessions` は `TOP_N`（10件）に切り詰められる
- `top_redundant_sessions` の `user_instruction` は切り詰めずそのまま出力する（Facts の再現性を優先し、要約はレポート生成側の所見に任せる）
- `redundant_access_waste` は `token_usage` が記録されているセッションのみを対象にした近似値であり、実測値ではない（`sessions_with_data` で算出に使えたセッション数を明示する）
- `duration_ms_stats` はこの機能追加前に flush されたセッション（`[Hook処理時間]` セクションを持たない）を自然にゼロサンプルとして扱う。全セッションが旧フォーマットの場合は `sample_count: 0` のゼロ値スタッツを返す
- `by_phase`（issue #308）は `[phase:count, ...]` サフィックスを持たない旧フォーマットの重複行を自然に `{}` として扱う。全セッションが旧フォーマットの場合、`top_duplicate_files` の各エントリの `by_phase` は空 dict になる
- `narrowed_count` / `narrowed_read_ratio_pct`（issue #363）も同様に、`(narrowed:N)` サフィックスや `(絞り込み読み: N)` を持たない旧フォーマットのログを自然に `0` として扱う。全セッションが旧フォーマットの場合、`narrowed_read_ratio_pct` は `0` になる（実際に絞り込み読みが0件だったのか、単に旧フォーマットで記録されていないだけなのかは区別できない）

## 変更履歴（git log より自動生成）

- d2cd65b feat(#308): add phase-tagged duplicate access breakdown to /analyze-access
- a565c97 feat(#252): add hook execution-time aggregation to /analyze-* commands
- 594905d feat(#216): redesign /analyze-* reports around KPI dashboards and findings
- 8d0793a feat(#214): track per-session redundant file reads in /analyze-access
- d7a7627 feat(#212): add /analyze-access, /analyze-auto-approve, /analyze-token-usage log analysis commands
