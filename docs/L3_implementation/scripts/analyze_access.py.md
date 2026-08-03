# `scripts/analyze_access.py` specification

## 目的・役割

`logs/access/*.log`（`hooks/log-access-stop.sh` が記録するセッション単位のアクセスログ）をパースし、集計結果を JSON として標準出力へ出力する。HTML生成・分析文の作成は行わない（`commands/analyze-access.md` が担う）。

根拠: `scripts/analyze_access.py:1-6`

## 動作の概要

1. ログはセッション毎に `---` のみの行で区切られたブロック形式で、各ブロックは `[日時]` / `[ユーザーからの指示内容]` / `[アクセスサマリ]` / `[フェーズ別アクセス順序]` / `[修正したファイル]` / `[トークン使用量]` の固定セクションヘッダを持つ（`[トークン使用量]` は transcript が無い場合省略される）
2. `split_blocks()` でブロックに分割し、`split_sections()` で各ブロックをセクション名 → 本文の辞書に変換する
3. セクションごとに正規表現でパースする: `parse_summary()`（総アクセス数・重複ファイル）、`parse_modified_files()`、`parse_token_usage()`。`[フェーズ別アクセス順序]` セクションは既存のセクション境界検出（`SECTION_HEADERS`）には残すが、内容はパースしない（本スクリプトの集計対象外）
4. `load_sessions(months)` で対象月の全ログファイルを読み、セッションのリストを作る
5. `aggregate(months, sessions)` でセッション横断の集計を行う: 重複ファイルの上位N件、セッション単位の無駄な再読み込み集計、および `redundant_access_waste()` による損失推定
6. `main()` で `lib.analyze_common` の共通CLI・月解決処理を呼び、結果を JSON として出力する

`session["duplicates"]` は `hooks/log-access-stop.sh` 側で `group_by(.path)` によりセッション単位で既に重複検出済みのリストである。この性質を利用し、`aggregate()` は各セッションの `duplicates` から「同一セッション内で同じファイルを何度も読んで無駄になった回数」（`count - 1` の合計）を `redundant_accesses_total` として集計し、`top_redundant_sessions()` で無駄な再読み込みが多いセッション上位（日時・指示内容・無駄な再読み込み回数・重複ファイル一覧・`modified`）を抽出する。`modified` は `session["modified_files"]` が非空かどうかの真偽値で、「読み直しただけで実際には何も変更しなかった」セッションを一目で判別できるようにするためのフィールドである。既存の `top_duplicate_files`（全セッション横断で重複カウントを単純合算したもの）はセッション横断の傾向把握用として残す。

`redundant_access_waste()` は、`duplicates` と `token_usage` の両方を持つセッションについて「セッション内の1アクセスあたりの平均トークン/コスト（`token_usage.total または cost_usd` ÷ `total_accesses`）」を近似単価とし、これに無駄な再読み込み回数を掛けて損失トークン数・損失コストを推定する。この関数だけが `duplicates`（頻度）と実際の損失（インパクト）を直接結びつける — 他の Fact はすべて頻度のみを報告する。

根拠: `scripts/analyze_access.py:70-92`, `scripts/analyze_access.py:148-230`

## 主要な判定ロジック・フロー

- ブロック区切りは正規表現 `^---$`（複数行モード）による厳密一致とし、ユーザー指示文中に偶然 `---` という語が単独行で現れないことを前提とする
- セクション本文の抽出は既知の6ヘッダのみを対象にした `SECTION_RE` で行い、`[フェーズ別アクセス順序]` セクション内部に現れる `[work] N件` のようなネストした角括弧はセクション境界として誤認しない（`SECTION_RE` に含まれないヘッダ名のため）
- ファイルは `errors="replace"` で読み込み、過去のログ破損（マルチバイト文字の途中切断。issue #194 で修正済みの旧バグに起因）があっても解析全体を失敗させない

根拠: `scripts/analyze_access.py:74-81`, `scripts/analyze_access.py:135`

## 重要な設計判断とその理由

Facts の再現性を担保するため、集計はすべて決定的な正規表現パースで行い、AI による要約や推測を混在させない。`commands/analyze-access.md` 側はこの JSON のみを根拠として Key Findings / Proposals を執筆する設計になっている。

`/analyze-access` の目的は「同一セッション内の重複読み込みロスの特定」に一本化されているため、この目的と直接関係しないセッション横断の一般的な生産性指標（フェーズ別/ツール別アクセス数、修正頻度上位ファイル、修正ゼロセッション比率）、および `/analyze-token-usage` の守備範囲と重複するセッション横断の汎用トークン集計は、集計対象から外している（issue #216）。目的外の指標を混在させると、レポートが「重複読み込みのロス」という単一の問いに答えられなくなるため。

## 統合ポイント

- 入力: `logs/access/<YYYY-MM>.log`（`hooks/log-access-stop.sh` が生成）
- 共通処理: `scripts/lib/analyze_common.py`
- 呼び出し元: `commands/analyze-access.md`
- テスト: `tests/scripts/test_analyze_access.py`

## 注意事項・既知の制限

- `[修正したファイル]` セクションが空（変更なし）の場合、`parse_modified_files()` は空リストを返す
- `top_duplicate_files` / `top_redundant_sessions` は `TOP_N`（10件）に切り詰められる
- `top_redundant_sessions` の `user_instruction` は切り詰めずそのまま出力する（Facts の再現性を優先し、要約はレポート生成側の所見に任せる）
- `redundant_access_waste` は `token_usage` が記録されているセッションのみを対象にした近似値であり、実測値ではない（`sessions_with_data` で算出に使えたセッション数を明示する）

## 変更履歴（git log より自動生成）

- 594905d feat(#216): redesign /analyze-* reports around KPI dashboards and findings
- 8d0793a feat(#214): track per-session redundant file reads in /analyze-access
- d7a7627 feat(#212): add /analyze-access, /analyze-auto-approve, /analyze-token-usage log analysis commands
