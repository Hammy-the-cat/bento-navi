# Cloudflare店舗データへの移行

## 構成

- GitHub ActionsでGeofabrikの日本8地域（北陸は中部、沖縄は九州）を最大2地域ずつ処理する。
- osmiumで対象カテゴリを抽出し、道路・建物などの不要な原データは配信しない。
- Pythonで店舗名・座標・カテゴリ・営業時間などに絞り、緯度経度0.1度ごとのJSONに分割する。
- 保存時はJSONを `shops.pack` に連結し、manifestに各地域の開始位置と長さ・ハッシュを記録。WorkerはR2 Range Readで必要な部分だけ読む。
- 1版あたりデータ本体とmanifestの2ファイル。数千回の個別ファイル転送を避け、更新時の通信回数とR2操作数を削減する。
- R2 `bento-navi-shop-data` に版ごとに保存。全ファイルを照合後、最後に `active.json` を切り替える。
- 既存WorkerのURLと `{elements: [...]}` 形式を維持し、既存iOSアプリからも使える構成。
- 検索半径に重なる周辺タイルだけを最大4並列で読み、正確な距離で絞る。全国データを端末へ送らない。
- スプレッドシート由来の11,022件は独立した原本・アプリ内カタログとして維持。外部店舗と既存の重複除去処理で合流する。
- 会場名の住所検索（Nominatim）、地図タイル、iOSビルド（Codemagic）は変更していない。

## 初回加工結果

- GitHub Actions: https://github.com/Hammy-the-cat/bento-navi/actions/runs/35819952489
- 初回公開データ版: `35819952489-1-packed`
- GitHub Actionsで梱包・13地点検証まで完了したデータ版: `35820999406-1`。本番へ更新し、前回版を保持する動作も確認した。
- 完成データのActions: https://github.com/Hammy-the-cat/bento-navi/actions/runs/35820999406
- 元データ時点: 2026-09-22T20:22:59Z
- OSM識別子の重複除去後: 102,288件
- 2,549タイル、17,631,372バイト（約17.6MB）、最大タイル552,529バイト。
- manifestは数百KB（索引・元データ・チェックサム）。
- PCには加工済みの約18MBだけ取得。数GBの元データと形状加工はGitHub上で処理した。
- ローカルの加工済みデータで全国9地域、報告された3会場、那覇の13地点を検証。全地点で店舗あり、半径外・OSM識別子重複なし。
- OSM件数は飲食店・コンビニ・スーパー等も含む。「調査済みの弁当専門店数」ではない。
- OSMに存在しない店舗、閉店情報の未反映、座標のない店舗はこの仕組みだけでは補完できない。

## 更新と異常時

- 全8地域の取得、元データ時刻、チェックサム、データ件数、サイズ、13地点の検索を検証する。
- 取得失敗、7日を超える古い元データ、地域の件数が前回から15%以上減った場合は公開を止める。
- アップロード途中の版は本番から参照しない。公開前にR2から全タイルを読み戻して一致を確認する。
- `active.json` は条件付き書き込みを使い、同時更新で上書きしない。
- 切り替え前の版のポインタを `previous` に残す。古い版のファイルは初期段階では自動削除しない。
- 存在するはずのタイルが欠けた場合は503を返す。障害を「店舗0件」にしない。
- 既存アプリは通信失敗時に登録済み店舗を維持する。予備のOverpassアクセスも既存アプリに残る。
- R2の旧版は1版約18MB。週次で毎回保存すると年間約1GBの増加見込み（件数が同程度の場合）。保存世代の自動整理は未実装。
- Actionsの地域抽出物は7日、完成データのartifactは14日保持。生のPBFはartifactに保存しない。

## 定期更新の接続設定

ワークフローの予定は毎週月曜03:23 JST。GitHubの定期実行はmainブランチ上で有効になる。
本番公開処理は `SHOP_DATA_PUBLISH=true` の場合だけ実行する。
未設定の場合は定期実行の加工ジョブも開始しない。初回移行は既存のWrangler認証で実施。

GitHub repository variables:

- `R2_ACCOUNT_ID`: CloudflareのアカウントID
- `SHOP_DATA_PUBLISH`: 初回配信検証と専用キーの設定が終わるまで設定しない

GitHub repository secrets:

- `SHOP_DATA_R2_ACCESS_KEY_ID`
- `SHOP_DATA_R2_SECRET_ACCESS_KEY`

R2キーの権限は専用バケットだけのObject Read & Write。キーをリポジトリ、ログ、ドキュメント、作業用JSONへ保存しない。
Cloudflareアカウント全体の管理権限や他のバケットへのアクセスは不要。

## 検証と運用

```powershell
node --test workers/overpass-proxy/src/*.test.mjs
python -m unittest discover -s tool/shop_data -p 'test_*.py'
python tool/check_shop_catalog.py
node tool/shop_data/check.mjs <dataset-directory> <report.json>
node tool/shop_data/check.mjs https://bento-navi-shop-data-preview.excitedcherry0909.workers.dev <report.json>
```

R2配信を設定したWorkerの `/health` で版・件数・元データ時刻を確認する。
`/data/manifest.json` と `/data/<version>/tiles/<cell>.json` からOSM派生データを取得できる。
OSMデータはODbL、帰属は © OpenStreetMap contributors。調査シートとは別データとして管理する。

## 配信確認

- 検証用Workerで13地点すべて成功。店舗検索APIは153〜1,293ms。
- 本番Workerへ反映済み: `25ae2767-2db5-4886-8e03-0ca781fa257c`。
- 本番URLで13地点すべて成功。店舗検索APIは57〜495ms（キャッシュ効果を含む）。
- 東京駅の500mと10kmも成功（それぞれ39件、7,983件）。
- 同じBentoServiceを使うWindows上の実通信テスト: 帯山中学校103件/817ms、アイビースタジアム14件/90ms、市場中学校332件/197ms。調査済み店舗と重複除去後の件数。
- Flutter静的解析は問題なし、既存自動テスト39件通過。Worker/加工/公開処理の自動テスト14件通過。
- iPhone実機での体感速度は未測定。会場名の住所検索や地図表示の外部依存は残る。
- 自動更新用R2キーの発行とGitHub Secretsへの保存はユーザー確認待ち。週次の本番自動更新はまだ有効化していない。

参考:

- https://download.geofabrik.de/asia/japan.html
- https://docs.osmcode.org/osmium/latest/osmium-export.html
- https://developers.cloudflare.com/r2/api/workers/workers-api-reference/
- https://developers.cloudflare.com/r2/api/s3/api/
