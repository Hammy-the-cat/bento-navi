# 審査差し戻し(2026-08-10 Guideline 2.1)への回答 下書き

Submission ID: `34c010d3-492e-4691-9c34-bb7df3c0d368`

Appleから7項目の追加情報を求められた。①②は実機作業が必要なため未確定。
③〜⑦はここに下書き済み。**Resolution Centerへの返信は英語で行う**
(App Reviewチームは英語が既定言語のため、確実に伝わる方を優先する)。

---

## ① スクリーン録画（実機で撮影・要ユーザー作業）

台本は `docs/appstore_review_recording_script.md` を参照。

## ② テスト機種・OSバージョン

```
The app was tested on a physical iPhone 15 running iOS 26.6 via
TestFlight before this submission.
```

※ 動画では位置情報の許可ダイアログが映っていない（撮影時点で既に許可済みだったため）。
　 ①の動画文脈に、下記の一文を添えて補足する。

```
Note: In the attached recording, the location permission had already
been granted from a previous test session, so the system prompt does
not appear. The purpose string is declared in Info.plist
(NSLocationWhenInUseUsageDescription) and is only requested when the
user taps the "現在地" (Current Location) button.
```

---

## ③ アプリの機能・対象ユーザー・解決する課題

```
べんとうナビ (Bento Navi) helps people find shops selling bento
(Japanese boxed meals) near a venue they are unfamiliar with.

Problem it solves:
When traveling to an away game, tournament, or unfamiliar venue for
sports events, users often don't know where to buy food nearby. This
app solves that by letting users search by venue name and instantly
see nearby convenience stores, supermarkets, and bento shops sorted
by distance.

Target audience:
- Parents accompanying their children's sports club or team to away
  games
- Coaches and team leaders traveling with a team
- Athletes competing at away tournaments
- Anyone visiting an unfamiliar area (business trips, travel) who
  needs to find food quickly

Value provided:
- Search any venue name or address, works nationwide in Japan
- Results sorted by distance with walking time estimates
- Filter by category (convenience store / supermarket / bento &
  deli / bakery / fast food / takeout-friendly restaurants)
- Map view and route guidance via Google Maps
- Share search results with teammates via a link (no re-searching
  needed)
- Articles with practical tips (what to eat before a game, food
  safety in summer, bulk-buying for a team, etc.)
```

---

## ④ セットアップ方法・主要機能へのアクセス手順

```
No account, login, or sign-up is required. All features are
available immediately after launch.

Steps to use the core feature:
1. Launch the app.
2. Enter a venue name or address in the search field (e.g. "県総合
   運動公園 宮崎"), or tap "現在地" (Current Location) to use the
   device's GPS instead.
3. Select a search radius (500m–3km).
4. Tap "会場周辺を検索" (Search Nearby) to see a distance-sorted
   list of shops.
5. Switch between list view and map view using the tabs above the
   results.
6. Filter results by category using the chips (convenience store,
   supermarket, etc.).
7. Tap "経路" (Route) on any shop to open directions in Google Maps.

There is no demo account or credentials needed since the app has no
authentication.
```

---

## ⑤ 外部サービス・ツール一覧

```
The app uses the following third-party services to deliver its core
functionality, all of which are free, public APIs with no API key
required:

- OpenStreetMap Nominatim — geocoding (converting a venue name into
  coordinates)
- Overpass API (OpenStreetMap) — searching for nearby shops
- OpenStreetMap tile servers — rendering the map
- Google Maps (via a standard maps: URL) — opened only when the user
  taps "Route" to get walking directions; this is a simple external
  link, not an embedded SDK

No advertising SDK is included in this version. No analytics,
authentication, or payment services are used.
```

---

## ⑥ 地域差

```
The app functions consistently across all regions. The only
distribution setting is Japan, and search functionality itself works
for any location worldwide that OpenStreetMap has data for, though
the app's marketing and content (articles, UI text) are written in
Japanese for a Japanese audience.
```

---

## ⑦ 規制業種・第三者保護素材

```
The app is not part of a regulated industry (no health, financial,
or legal services).

The app displays shop location data and map tiles from OpenStreetMap,
licensed under the Open Database License (ODbL), which permits reuse
with attribution. The app displays the required attribution "地図
データ © OpenStreetMap contributors" (Map data © OpenStreetMap
contributors) on every map screen and in the footer, satisfying the
ODbL's attribution requirement. No API key or special authorization
is required to use these public OpenStreetMap services.
```
