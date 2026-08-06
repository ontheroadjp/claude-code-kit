# `skills/coding-react/SKILL.md` specification

## 目的・役割

Codex向けの薄いwrapperとしてReact規約の依存順序を定義する。

## 動作の概要

general、JavaScript、必要ならTypeScript、Reactの順にcommandをReadする。

根拠: `skills/coding-react/SKILL.md:1-22`

## 重要な設計判断

規約本文をskillへ複製せず`commands/coding-react.md`をSource of Truthにする。

## 統合ポイント

`install.sh`のwildcardにより`~/.codex/skills/coding-react/`へsymlinkされる。

## 注意事項・既知の制限

参照commandが欠ける場合は適用を中断する。
