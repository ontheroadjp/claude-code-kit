# Policy

## 1. Repository を workflow の authority とする

workflow の構造、必須 gate、工程順序、required artifact、approval point は repository に記録し、agent の一時的な conversation context や都度判断だけに依存させない。

agent は workflow definition を独自に省略、置換、統合しない。workflow 内部の具体的な problem solving は agent が担う。

## 2. Work contract を実装の基本単位とする

継続開発における実装作業は、目的、背景、constraint、scope、done criteria が人間と AI の間で合意された work contract を基本単位とする。

要求が未解決の場合は実装と分離して検討し、agent が未合意事項を推測で確定しない。新しい unresolved concern が見つかった場合、実装を継続するか検討へ戻すかは人間が決定する。

## 3. Direction と Approval を人間が保持する

人間は、要求の方向性、priority、scope、実装単位、plan approval、result acceptance、および重要な state change を決定する。

agent は facts、assessment、options、risks、proposal を提示できるが、それらを人間の決定として扱わない。

## 4. Guardrail と Judgment を分離する

安全性、一貫性、traceability に関わる guardrail は agent の自由判断から分離する。agent は guardrail の内部で、調査、設計、実装、test、rollback、exception handling の具体策を判断する。

Agentic Fallback を利用する場合も、mandatory gate、work contract、approval boundary を迂回しない。

## 5. Effectful Operation を保守的に扱う

read-only investigation と state-changing operation を明確に区別する。effectful operation は対象、前提、影響、recoverability を確認して実行する。

不可逆な操作、既存作業を失う可能性がある操作、shared state に影響する操作は、人間の明示的な control の下で扱う。

## 6. Documentation と Implementation の整合を維持する

implementation と diff を現在の事実とし、documentation はその事実と design intent を根拠付きで説明する。

正規化済み documentation は調査の起点として再利用するが、stale citation や implementation drift の可能性を考慮し、対象箇所が期待する内容を含むことを確認する。

## 7. Evidence に基づいて workflow を改善する

workflow rule の追加、維持、緩和は execution evidence に基づいて判断する。固定手順が rework、risk、variance を防ぐ場合は維持し、継続的に waste を生む場合は簡素化または agent delegation を検討する。

現在機能している procedure は、明確な改善根拠なしに変更しない。agent の能力向上によって固定手順より良い判断が可能になった場合は、guardrail を維持しながら段階的に判断を戻す。

## 8. L0 の変更を人間が管理する

L0 は project の目的、価値判断、authority boundary を記録する。implementation diff への機械的な追従対象とはせず、追加・変更は人間の明示的な検討と承認を必要とする。
