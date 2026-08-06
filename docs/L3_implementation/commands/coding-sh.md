# `/coding-sh` specification

## 目的・役割

`coding-general`にshell固有のportabilityとerror handling規約を重ねる。

## 動作の概要

対象shellを明示し、そのshellが提供する機能だけを使う。直接実行するBashでは`set -euo pipefail`を既定とし、variable quoting、parameter expansion、理由付きShellCheck抑制を要求する。

根拠: `commands/coding-sh.md:1-88`

## 重要な設計判断

`#!/bin/bash`を普遍的に強制せず、POSIX互換要件、配置環境、既存shebang方針を優先する。sourceされるlibraryと意図的なbest-effort処理はfail-fastの例外とする。

## 統合ポイント

task/patchが`.sh`変更前に読み、ShellCheckが機械検証する。

## 注意事項・既知の制限

POSIX `sh`では未定義の`pipefail`を使用しない。抑制はrepository全体ではなく最小scopeへ閉じ込める。
