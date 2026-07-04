# 🍱 べんとうナビ (Bento Navi)

スポーツの試合・大会で知らない土地に行ったとき、会場の近くで弁当が買える店をすぐに見つけられる Flutter 製 Web アプリ。

## 機能

- **会場名・住所で検索** — OpenStreetMap Nominatim によるジオコーディング。「県名+施設名」で見つからない場合も多段フォールバックで自動再検索
- **現在地から検索** — ブラウザの位置情報を利用
- **周辺店舗を距離順に表示** — コンビニ / スーパー / 弁当・惣菜 / パン屋 / ファストフードを Overpass API で検索（ミラー自動フォールバック付き）
- **地図表示** — flutter_map + OSM タイル。カテゴリ色分けマーカー
- **チーム共有リンク** — 会場の座標を埋め込んだ URL をワンタップコピー
- **検索履歴** — 最近の検索 6 件をワンタップ再検索
- **Google マップ経路連携** / 検索範囲切替 (500m〜3km) / カテゴリ絞り込み

## 開発

```bash
flutter pub get
flutter run -d chrome        # 開発実行
flutter test                 # テスト
flutter build web --release  # 本番ビルド (build/web に出力)
```

- Flutter 3.7.12 / Dart 2.19.6 対応（record 構文などの Dart 3 機能は不使用）
- プラグイン追加後は `flutter clean` してからビルドすること（web_plugin_registrant の再生成のため）

## 収益化 (Google AdSense)

広告枠は実装済み。公開・審査後に以下 2 箇所へ ID を設定して再ビルドする:

1. `lib/config/ad_config.dart` — `adsenseClient` とスロット ID
2. `web/index.html` — コメントアウトされたスクリプトを解除して ID 記入

審査用の静的ページ: `web/guide.html`（使い方）/ `web/tips.html`（遠征弁当のコツ集）/ `web/privacy.html`（プライバシーポリシー）

## クレジット

- 地図データ・店舗データ: © OpenStreetMap contributors
- ジオコーディング: Nominatim / 店舗検索: Overpass API
