# `global/CLAUDE.md` specification

## 目的・役割

`global/CLAUDE.md` は、このリポジトリが提供する Claude Code / Codex CLI 向け AI 運用フレームワークの配布用ファイルである。`~/.claude/CLAUDE.md`（Claude Code のユーザーレベル global instructions）と `~/.codex/AGENTS.md`（Codex CLI の home-level AGENTS.md）の両方から手動 symlink される single source of truth であり、どのリポジトリで作業していても常にロードされる。

根拠: `README.md`（Global AI Instructions）, `docs/.ai/repo.profile.json`（`deploy.claude_md`, `deploy.codex_agents_md`）, issue #365

## 動作の概要

分離直後の現時点では、リポジトリルートの project-local `CLAUDE.md`（`docs/L3_implementation/CLAUDE.md` 参照）と全く同一の内容を持つ。今後は両ファイルが別々の目的で編集されていく:

- `global/CLAUDE.md`: どのリポジトリでも成り立つ汎用的な振る舞い（command routing、resolve-then-embed、絞り込み読みの検証等）を `/work` の通常フローで育てる
- ルート `CLAUDE.md`: このリポジトリ固有の事実（symlink-only の実装詳細、`site/` の技術選定等）を `/init-docs` が観測・再生成する

根拠: issue #365

## 主要な判定ロジック・フロー

内容は分離元の `CLAUDE.md`（project-local）と同一のため、個別の判定ロジックは `docs/L3_implementation/CLAUDE.md` を参照。

## 重要な設計判断

配布物と project-local ファイルを同一ファイルにできない理由、および分離の経緯は `docs/L3_implementation/CLAUDE.md` の「配布用ファイルと project-local ファイルの分離（issue #365）」に記録している（重複記載を避けるため参照のみ）。

## 統合ポイント

- `~/.claude/CLAUDE.md` ← 手動 symlink（`README.md` Global AI Instructions）
- `~/.codex/AGENTS.md` ← 手動 symlink（同上）。Codex CLI は `~/.codex/AGENTS.md` から project root を経て cwd までの AGENTS.md を加算的に連結する仕様のため、このファイルはどのリポジトリでも最上位層として読まれる
- `install.sh` はこの配布経路を自動化しない（既存の CLAUDE.md 配布方針を踏襲し、意図的に手動のまま）

## 注意事項・既知の制限

- 分離直後は project-local `CLAUDE.md` と内容が重複している。今後の編集で内容が乖離していくのは想定通りであり、同期を維持する必要はない
- `install.sh` にこのファイルの配布ロジックはないため、新規セットアップ時は `README.md` の手動 symlink 手順を必ず実行する必要がある

## 変更履歴（git log より自動生成）

- c4b0aeb chore(#365): split distributed CLAUDE.md from this repo's project-local CLAUDE.md
