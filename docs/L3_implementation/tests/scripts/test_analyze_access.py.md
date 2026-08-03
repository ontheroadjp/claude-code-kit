# `tests/scripts/test_analyze_access.py` specification

## 目的・役割

`scripts/analyze_access.py` のブロック分割・セクションパース・集計ロジックを検証する pytest テスト。

根拠: `tests/scripts/test_analyze_access.py:1-14`

## 動作概要

固定の2セッション分（重複あり・トークン使用量あり / 重複なし・トークン使用量なし）の合成ログ文字列 `LOG_CONTENT` を使い、以下を検証する:

- `split_blocks()` がブロックを正しく2件に分割すること
- `parse_session()` が総アクセス数・重複ファイル・修正ファイル・トークン使用量を正しく抽出すること
- 重複なし（`重複アクセス: なし`）・トークン使用量セクション欠如のケースを正しく `[]` / `None` として扱うこと
- `monkeypatch` で `lib.analyze_common.repo_root` を `tmp_path` に差し替え、`load_sessions()` → `aggregate()` を通した集計値（セッション数・総アクセス数・修正ゼロ比率・上位ファイル・フェーズ/ツール別合計・トークン使用量合計）が期待値と一致すること
- `main()` を `sys.argv` 差し替えで直接実行し、標準出力が妥当な JSON であること

根拠: `tests/scripts/test_analyze_access.py:70-146`

## 重要な設計判断

`repo_root()` を monkeypatch することで、実ログファイルシステムに触れずに `logs/access/<month>.log` の読み込みパスだけを差し替えている。これにより実行環境（このリポジトリの `logs/`）に依存しない再現可能なテストになっている。

## 統合ポイント

- 対象: `scripts/analyze_access.py`, `scripts/lib/analyze_common.py`
- 実行: `python3 -m pytest tests/scripts/test_analyze_access.py`
- `tests/scripts/conftest.py` が `scripts/` を `sys.path` に追加している

## 注意事項・既知の制限

合成ログは実ログのごく一部のパターン（重複あり/なし、トークン使用量あり/なし）のみをカバーする。フェーズが複数（`work`/`task`/`patch` 等）に渡るケースは明示的にはテストしていない。
