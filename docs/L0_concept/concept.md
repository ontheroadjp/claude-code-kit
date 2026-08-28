# Concept

## 1. この toolkit の目的

この toolkit は、AI coding agent を継続的なソフトウェア開発で安全、効率的、再現可能に利用するための汎用実行環境である。

単なる command、prompt、skill の集合ではない。異なる構成を持つ repository を共通の情報モデルへ正規化し、その上で調査、要件整理、実装、検証、documentation synchronization、Git 操作、delivery を安定して実行できることを目的とする。

AI agent の自律性そのものを最大化することは目的としない。重視するのは、正確性、再現性、安全性、token efficiency、実行速度、見落としの少なさ、および継続的に改善できることである。

本 toolkit の中心原則は次である。

> **workflow is defined by the repository; solution is designed by the agent; direction and approval remain with the human.**

作業の構造、必須の境界、成果物、承認点は repository 側で定義する。その内部で必要になる調査、具体的な実装方法、trade-off、検証方法などの文脈依存の問題解決は AI に委ねる。要求の方向性、優先順位、scope、acceptance、および重要な状態変更の承認は人間が保持する。

## 2. Repository Normalization

repository ごとに、directory structure、documentation、技術 stack、起動方法、test 方法、設計情報の配置は異なる。

AI agent が作業のたびにこれらをゼロから探索すると、不要な読み込み、同一情報の再探索、調査品質のばらつき、必要情報の見落とし、token と時間の浪費が生じる。

そのため、最初に repository を観測し、基本情報、構造と責務、開発・test・運用方法、実装仕様、設計方針、根拠、後続調査の入口を共通の Repository Model へ正規化する。後続の workflow と agent は、正規化済み情報を標準の探索起点として利用する。

## 3. 一度理解したことを毎回再探索しない

一度確認した repository 情報は、構造化された documentation と machine-readable profile に保持し、後続作業ではそこから必要な実装事実へ到達する。

これは単なる cache ではない。必要な情報へ短い根拠付き経路を用意し、agent が扱う探索空間そのものを小さくするための仕組みである。

ただし、保存された情報を無条件に真実とは扱わない。implementation が変化した可能性や citation のずれがある場合は、現在の implementation と diff を最終的な事実として再検証する。

## 4. Issue-driven Development

継続開発における実装作業は、人間と AI の間で目的、制約、scope、完了条件が合意された work contract を基本単位とする。その標準的な表現が implementation-ready Issue である。

Issue は単なる task list ではない。要求整理と実装を分離し、作業単位と変更理由を追跡可能にし、実装、test、commit、delivery を同じ文脈へ結び付ける。

要求が十分に整理されていない場合は、実装へ進む前に人間と AI が方向性、制約、scope、完了条件を検討する。要求整理は一方向の state transition ではなく、後続の調整で新しい未解決事項が見つかれば、人間の判断で検討段階へ戻せる。

## 5. 固定するもの、AI に委ねるもの、人間が決めるもの

手続き型 workflow と AI の判断能力を対立させない。再現性を必要とする構造、手順、境界を固定し、その枠内で文脈依存の判断を AI に委ね、方向性と承認を人間が保持する。

### 固定するもの

継続開発の安定性を支える主要な固定点は次の三つである。

1. **Documentation structure** — repository を共通の情報モデルへ正規化し、implementation との整合を維持する。
2. **Implementation work contract** — 目的、制約、scope、完了条件を合意済みの作業単位として保持する。
3. **Implementation workflow** — 必須 gate、工程順序、成果物、承認点を agent の都度判断で省略・置換しない。

### AI に委ねるもの

固定された workflow の内部では、問題の性質や repository の状態によって最適解が変わる判断を AI に委ねる。

- Issue と要求の意図理解
- 必要な調査と追加情報の特定
- 変更対象の特定
- execution plan の策定
- implementation approach と design option の比較
- trade-off の評価
- 具体的な実装方法
- test と verification method の選択
- risk と rollback の検討
- exceptional case や未知の状況への対応

AI は固定手順を機械実行するだけではなく、固定された工程の中で目的達成の具体策を組み立てる。

### 人間が決めるもの

project direction と重要な状態変更の最終権限は人間が保持する。

- 要求の方向性、priority、scope
- 検討をいつ終了するか
- 実装単位をどの work contract として確定するか
- agent が策定した plan を承認するか
- 実装結果を受け入れるか、rework を求めるか
- 新しい論点を検討段階へ戻すか
- destructive operation や明示 approval を必要とする state change

## 6. Deterministic Fast Path

十分に一般化でき、繰り返し有効であることが確認された処理には、決定論的な実行経路を用意する。

固定された手順を持つこと自体は目的ではない。その手順が、無駄な探索を減らす、見落としを防ぐ、再現性を高める、token consumption を減らす、事故を防ぐという実用上の効果を持つ場合に採用する。

## 7. AI の判断を使う場所

すべての判断を決定論的に固定することも目的ではない。問題の性質や repository の状態によって最適解が変わる部分では、AI の reasoning ability を積極的に利用する。

原則は、固定すべき構造、手順、境界は固定し、その内部の文脈依存の判断を AI に委ねることである。

## 8. Agentic であること自体を目的にしない

agent の自由度が高いことと、開発結果が優れていることは同義ではない。自由度を上げることで、不要な探索、重複した tool execution、判断のばらつき、必要工程の省略、token consumption の増加が発生する場合がある。

AI に判断を委ねるか、procedure を固定するかは、思想的な好みではなく実際の性能で決める。評価基準は自律性ではなく、正確性、速度、token efficiency、再現性、安全性である。

## 9. Fast Path と Agentic Fallback

標準的な case では、正規化された Repository Model と Deterministic Fast Path を優先する。

標準経路だけでは十分な情報を得られない場合や未知の構成に遭遇した場合は、固定された guardrail と approval boundary を維持したまま、AI が追加調査や別の具体策を選択できる。

fallback は mandatory gate、work contract、guardrail、human approval を迂回する理由にはならない。

## 10. Guardrails と Judgment を分離する

安全性、一貫性、traceability に関わる rule は AI の自由判断に委ねない。既存作業を失わない、不明な状態で destructive operation を行わない、implementation と documentation の整合を維持する、未合意の方向性を agent が確定しない、必要な verification なしに完了扱いしない、といった事項は guardrail として扱う。

一方で、その guardrail を満たすための具体的な方法には、必要に応じて AI の判断を利用する。

## 11. Effectful Operation は保守的に扱う

調査や分析と、実際に state を変更する操作は区別する。repository、history、file、external service に影響する操作は、対象、前提、影響を確認し、可能な限り決定論的かつ保守的に扱う。

AI の reasoning ability は、effectful operation を無制限に自動化するためではなく、いつ実行すべきか、実行条件を満たしているか、どの risk があるかを判断するために利用する。

## 12. Documentation は AI の作業基盤である

documentation は人間向けの説明資料だけではない。AI が repository を効率的かつ正確に理解するための構造化された作業基盤でもある。

documentation には、implementation facts、design intent、repository structure、根拠、開発・verification method を適切な粒度で保持する。implementation が変更された場合は関連 documentation も同期し、Repository Model が陳腐化しないよう維持する。

## 13. Observability に基づいて改善する

workflow の改善を感覚だけで行わない。token usage、tool access、duplicate discovery、approval friction、execution time、retry、failure、rework などを観測する。

固定手順が継続して rework や risk を防ぐ場合は維持する。反対に、固定手順が繰り返し waste を生む、または contextual variation に対応できない場合は、その部分を簡素化するか agent へ判断を戻す候補とする。

この toolkit は手続きを増やし続ける system ではなく、execution evidence に基づいて必要な制約と不要な制約を継続的に見直す system を目指す。
