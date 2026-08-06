# /coding-nextjs

まず `coding-general`、`coding-js`、`coding-ts`、`coding-react` を参照し、その後以下のNext.js固有ルールを適用すること。Next.jsはversion間の変化が大きいため、導入済みversionの公式ドキュメント、型定義、設定を確認し、記憶したAPIへ合わせて既存コードを変更しない。

---

## 原則とアンチパターン

### 1. server/client境界を意図的に設計する

browser API、client state、event handlerが必要な最小subtreeだけをClient Componentにする。対話性のないpageやlayout全体へ惰性でclient directiveを付けない。境界を越すpropsは導入済みversionが許すserializableな値にする。

### 2. data sourceへserverから直接アクセスする

Server Componentやserver-side処理から、同一applicationのRoute HandlerをHTTP経由で呼ばない。認証・validation・domain logicを共有moduleへ分離し、serverから直接呼ぶ。公開HTTP境界のintegration testなど、HTTP自体が対象の場合は例外とする。

### 3. 認証と認可を境界ごとに実施する

middleware、layout、client-side redirectだけを認可境界にしない。mutation、server action、Route Handler、data accessの実行地点で権限を確認する。UIを隠すことをsecurity controlとして扱わない。

### 4. cachingとfreshnessを明示する

dataの更新頻度と共有範囲を決めずにcache optionを追加しない。広すぎる全体無効化や、mutation後の無効化漏れを避ける。cache、revalidation、dynamic renderingの正確な意味は導入済みversionで確認する。

### 5. rendering modeを偶然に変えない

request固有API、runtime指定、dynamic APIを深いutilityへ隠し、route全体のrendering/caching特性を意図せず変えない。変更前後のbuild outputまたはframework提供の診断で確認する。

### 6. routing規約を責務分離に使う

root layoutへ全pageのdata fetching、巨大provider tree、request別分岐を集中させない。loading、error、not-found境界を必要なsegmentへ配置する。file conventionとreserved filenameは導入済みversionの公式資料で確認する。

### 7. server-onlyの情報をclient bundleへ入れない

secret、privileged SDK、server-only moduleをClient Componentからimportしない。公開可能な環境変数とsecretを明確に分け、環境変数の命名だけに依存せずbundle境界を検証する。

### 8. mutationを安全に扱う

入力をruntimeで検証し、認可、CSRFを含むrequest originの前提、idempotency、競合、error mappingを検討する。redirectやcache invalidationを成功前に実行しない。clientから渡されたidentityや価格を信頼しない。

### 9. framework機能を重複実装しない

frameworkが提供するmetadata、image、font、script、navigation、error boundary等を、要件確認なしに独自実装へ置換しない。一方、framework helperの利用自体を目的化せず、生成HTML、accessibility、performanceを検証する。
