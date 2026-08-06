# `skills/coding-nextjs/SKILL.md` specification

## 目的・役割

Codex向けの薄いwrapperとしてNext.js規約の依存順序を定義する。

## 動作の概要

general、JavaScript、TypeScript、React、Next.jsの順にcommandをReadする。

根拠: `skills/coding-nextjs/SKILL.md:1-21`

## 重要な設計判断

規約本文をskillへ複製せず`commands/coding-nextjs.md`をSource of Truthにする。

## 統合ポイント

`install.sh`のwildcardにより`~/.codex/skills/coding-nextjs/`へsymlinkされる。

## 注意事項・既知の制限

参照commandが欠ける場合は適用を中断する。
