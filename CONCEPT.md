# ISUCON5 決勝問題コンセプト

## 「間違ったマイクロサービス」

```
「よっしゃ、これからはマイクロサービスだ!」
「社長マイクロサービスとは？」
「細かいサービスをたばねてひとつのサービスとして提供するのだ。幸い我が社では既存の多数のサービスが多数の部署により提供されておる。」
「は。残念ながらどれもあまりヒットはしておりませんが。」
「おらんが、これらを束ね、まとめてユーザに提供すれば、こんなに便利なものはないだろう!」
「は。たしかに。」
「ということで多数のサービスを束ね、これを提供する。なーに簡単なことだ。」
「は。簡単でしょうか。」
「うむ。ということで作っておいた。ついては夕方の発表会をストリーミング中継し、大々的に売り出す」
「は。突然ですね。」
「ということでちょっと性能面を見ておいてくれんかね？ なーに、キミにとっては他部署のサービスを呼び出すだけだから簡単だろう! ガッハッハ!」
```

主催者側が予め多種類のWeb APIエンドポイントを用意し、参加者アプリケーションはユーザ(ベンチマーク)からのリクエストに応じてそれらを呼び、結果を統合してレスポンスを返すサービスとする。
外部APIはもちろん参加者にとってブラックボックスとなっており、参加者は送っているリクエストとレスポンスヘッダ、レスポンスボディの内容を精査する必要があるだろう。

## 技術的ポイント

HTTP APIエンドポイント関連のアイデアとしては以下のようなものがある

* 参照実装では最初は多数の呼び出し先に対して直列に(1-by-1で)呼び出すように書く (多数のAPIエンドポイントへの並列リクエストに書き換えられるかがキモ)
* Last-Modified, If-Modified-Since, Cache-Control, ETag などキャッシュ制御に関するHTTP仕様をフルに扱うAPIが存在する
* いっぽうそういったものを全く解釈しないものもある (が、コンテンツの中身から明らかに呼び出し元でキャッシュできるものがある)
* レスポンスまで必ず 0.5 秒待たせるなど、妙に遅いエンドポイントなどを含む
* あるエンポイントは呼び出しユーザ毎に1コネクションしか許さない(並列リクエストを許さない)が、そのエンドポイントに2リクエスト以上送る必要がある
* **そしてそのエンドポイントはHTTP/2対応している**のでHTTP/2並列リクエストが使える (プロトコルをhttpsのみ対応にしてヒントとする)
* HTTP APIエンドポイントを複数種類の言語で実装することでレスポンスヘッダや速度特性にバリエーションを出す

その他の技術的アイデアとしては以下のようなものがある

* PostgreSQLを使う(適度にボトルネックも作りたい)
* HTMLを返すリクエストハンドラとJSONを返すリクエストハンドラが存在する
* ユーザごとに(？) .js をテンプレートから生成して返す部分が存在するようにする(が、実はパターン数が決まっており静的生成できるようにする)
* 当然だがログイン機能とセッションの扱いが必要

ベンチマークについても以下のような点に配慮が必要

* ベンチマーカーはHTTP/1.1
* 1リクエスト-レスポンスが極めて遅いが高速化していったときにはかなり高スループットになる
* 並列度をかなり上げたベンチマーカーが必要
* Redirect先の変更時にLocationを追ってコンテンツ取得するケースも存在する
* JavaScriptファイルが壊れていないかどうか確認する方法が必要、一致チェックでいい？

## 今回の出題者にとってのポイント

* サーバサイドとして HTTP/2 を扱う (HTTP API エンドポイント)
* クライアントサイドに HTTP/2 を扱えるものは何があるかを知っておく(実装の必要はない)
* それなりに高性能なHTTP API エンドポイントを作ってホストする (h2o+mruby？ nginx+lua? go? そのほかLL？ 色々ありそう)
* PostgreSQL

## HTTP API アイデア (under construction)

### 2015年の日本の祝日情報API

プロトコル的に何も対応してない(しかも遅い)が日本の祝日なんて変わらないからキャッシュできるに決まってるだろJK

### 郵便番号→住所API

ユーザを超えて一度クエリされたものはキャッシュ可能: ただし本番計測ではフレッシュな(作業時間中は一度もクエリされなかった)データセットを使う

KEN_ALL.csv をきちんとparseできるライブラリが存在する言語で書くこと

### ユーザの予定リストを返すAPI

ただしある日についての1リクエストで1予定(と、他にまだ予定があるかどうか)しか返ってこないので直列リクエストが必要
「ユーザ x 日付」 の組合せがキーになるが、これも本番計測ではフレッシュなデータセットを使うこと

これはもうちょっと工夫できる余地があったほうがいいかな？ ベンチ1リクエストに対して複数の日付に関するAPI callが必要でそこは並列化できるとか？

### ユーザの謎のデータに対して謎のデータを返すAPI

イメージとしてはキーを与えると暗号化済みのデータを返してくれる、という感じ(適当なアルゴリズムで生成する, `key -> { sha512(key.char(0) + key.char(-1) + key) }` みたいな？)
HTTP/2 で並列に処理させられるサービスとしてはこのあたりが適当？
こいつももちろん遅い

### (ほか何かアイデア募集中)

4種類あれば十分？ もうあとふたつみっつ欲しい気がする
