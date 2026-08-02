# approval-safety shared helper specification

## 目的・役割

`hooks/lib/approval-safety.sh` は PreToolUse hook が共有する destructive Bash command 判定を提供する。`hooks/auto-approve-readonly.sh` と `hooks/guard-destructive-cmd.sh` が同じ判定を利用し、危険な command を allowlist や session-approved category より優先して block できるようにする。

根拠: `hooks/lib/approval-safety.sh:1-113`, `hooks/auto-approve-readonly.sh:20-21`, `hooks/guard-destructive-cmd.sh:14-24`

## 動作概要

`approval_safety_destructive_reason` は command 全体を受け取り、次の分類を順に検査する。

- system directory を対象とする recursive delete / permission change
- block device の overwrite、filesystem signature 操作、fork bomb
- Git history rewrite、force push、hard reset、working-tree discard、forced branch deletion、destructive stash operation

該当時は理由を標準出力へ返して成功し、非該当時は失敗 status を返す。呼び出し元は `approval_safety_emit_block` で理由を block decision JSON に変換する。

根拠: `hooks/lib/approval-safety.sh:26-113`

## Git force 判定

Git force operation は用途別の predicate に分離する。

- `approval_safety_is_force_push`: `--force` 系、`-f` を含む short option、leading `+refspec`
- `approval_safety_is_force_checkout`: checkout / switch の `-f` または `--force`
- `approval_safety_is_force_branch_delete`: `git branch` を含む shell segment ごとに、`-D`、または delete option と force option の組み合わせ（long option と combined short option を含む）を検査する

これらの predicate は destructive guard だけでなく、`tool:git_write` の session-approved fast path でも再利用する。fast path と後段 guard の判定差を作らないことが、session approval が destructive operation を迂回しないための重要な設計条件である。

branch force 判定は command 全体にある delete / force option を独立に検索しない。`git branch` から次の shell separator までを抽出して同一 segment 内の option だけを組み合わせる。これにより、`test -d ... && git branch --show-current && test -f ...` のような読み取り専用 compound command を forced deletion と誤認しない。

根拠: `hooks/lib/approval-safety.sh:4-31`, `hooks/lib/approval-safety.sh:72-107`, `hooks/auto-approve-readonly.sh:395-423`

## 統合ポイント

- `hooks/auto-approve-readonly.sh` は library を source し、session-approved 判定と command 全体の destructive guard に利用する。
- `hooks/guard-destructive-cmd.sh` は互換 wrapper として同じ reason function と JSON emitter を利用する。
- `tests/hooks/test-approval-hooks.sh` は auto-approve hook と guard wrapper の双方から Git force variants が block されることを検証する。

根拠: `hooks/auto-approve-readonly.sh:20-21`, `hooks/auto-approve-readonly.sh:395-423`, `hooks/auto-approve-readonly.sh:637-641`, `hooks/guard-destructive-cmd.sh:14-24`, `tests/hooks/test-approval-hooks.sh:261-313`

## 設計判断

Git force 判定を session-approved 側へ複製せず shared predicate とした。fast path は destructive guard より前に評価されるため、別々の regular expression を維持すると一方だけの更新によって bypass が生じる。共有 predicate により、新しい force variant は一箇所の変更で両経路から除外される。

複数 option の組み合わせを判定する predicate は同一 shell segment に scope を限定する。command 全体から各 option を別々に探すと、前後の無関係な `test -d` / `test -f` まで組み合わせて destructive と判断するためである。

## 注意事項・既知の制限

この helper は shell parser ではなく、command text に対する保守的な pattern matching である。安全と断定できない構文を実行する役割は持たず、呼び出し元の通常許可フローへ委ねる。comment と command の完全な構文解析は行わない。
