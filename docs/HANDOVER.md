# べんとうナビ 引き継ぎメモ（2026-08-08 時点）

新しいチャットで作業を再開するときは、まずこのファイルを読むこと。

---

## 1. これは何か

スポーツの遠征・大会で知らない土地に行ったとき、**会場周辺でお弁当が買える店を探す**アプリ。
Flutter 製で、**Web 版はすでに公開中**、**iOS 版は App Store 提出の直前**まで来ている。

---

## 2. 場所とURL

| 対象 | 場所 |
|---|---|
| **ローカルの正本** | `C:\Users\pw282\Dev\VIBECORDING\projects\bento_navi` |
| GitHub | https://github.com/Hammy-the-cat/bento-navi （public） |
| Web版（公開中） | https://hammy-the-cat.github.io/bento-navi/ |
| ルートサイト | https://hammy-the-cat.github.io/ （別リポジトリ `Hammy-the-cat.github.io`） |

> ⚠️ **`VIBECORDING\bento_navi`（ルート直下）は 2026-07-09 の整理で空になった旧場所。触らないこと。**
> ⚠️ 作業前に必ず `git -C projects\bento_navi log --oneline -1` で最新か確認する。
> 別セッションがコミットしていることがあるため、**ローカルが遅れている前提**で扱う。

### ブランチ運用
- `main` … ソース
- `gh-pages` … `build/web` の中身を force push して公開（Web版のデプロイ）

---

## 3. 環境

- **Flutter 3.44.4 / Dart 3.12.2**（2026-08にアップグレード済み）
- Windows のみ。**Mac は一切使っていない**（iOS ビルドは Codemagic のクラウド Mac）
- 開発者モードが無効なため、**プラグイン追加後は必ず `flutter clean`** が必要
  （やらないと `MissingPluginException` が出る）

---

## 4. 完了していること

### アプリ機能
- 会場名／現在地からの周辺店舗検索（Nominatim + Overpass API）
- 距離順リスト・地図表示（flutter_map 8）・カテゴリ絞り込み
- Googleマップ経路連携、チーム共有リンク（座標埋め込み）、検索履歴
- 調査済み店舗データ `assets/shops.json`（宮崎・鹿児島・長崎・佐賀など）

### iOS
- Apple Developer Program 登録済み（**Team ID: `73Y7T62D7C`** / 個人 / 更新日 2027-08-08）
- **Bundle ID: `com.bentonavi.app`**（App ID 登録済み）
- App Store Connect にアプリ作成済み（**App ID: `6799425026`** / SKU: `bento-navi-001`）
- Codemagic でビルド〜署名〜アップロードが**成功**。TestFlight で実機動作確認済み
- **アプリアイコン作成済み**（弁当箱モチーフ。`tool/make_icon.py` で再生成可能）

### コンテンツ
- 記事12ページ（使い方・遠征弁当のコツ・栄養・競技別・夏/冬・チーム・探し方・FAQ・運営者について・プライバシーポリシー）
- **App Store 掲載原稿**: `docs/appstore_listing.md`（文字数検証済み）

---

## 5. 残っている作業

| 優先 | 項目 | 補足 |
|---|---|---|
**提出作業は `docs/appstore_submit.md` に通しの手順書がある。**（スクショの並び順・掲載情報・審査メモ・年齢制限の質問票・提出時の質問まで網羅）

| 優先 | 項目 | 状態・補足 |
|---|---|---|
| — | Codemagic で再ビルド → TestFlight で確認 | ✅ **完了（2026-08-10）**。ビルド `1.0.0 (11)` = commit `59a8a82`（AdMob削除済み）。実機で広告枠なしのレイアウトを確認済み。**7〜10は広告入りなので使わないこと** |
| — | スクリーンショット | ✅ **完了（2026-08-10）**。`C:\Users\pw282\Downloads\bento-navi-screenshots\` に4枚（`1284×2778`）。`_未使用\` はWebページのスクショなので使わない |
| 1 | 掲載情報・審査情報の入力 | `docs/appstore_submit.md` §1〜4 |
| 2 | プライバシー申告 | `docs/appstore_privacy.md`。結論は「正確な位置情報／Appの機能／IDにリンクしない／トラッキングしない」の1項目だけ |
| 3 | 配信地域を**日本のみ**に | EU配信にはデジタルサービス法の事業者登録が必要 |
| 4 | 審査に提出 | `docs/appstore_submit.md` §8。落ちた場合の想定問答も同ファイル末尾にある |

### TestFlightで詰まった点（2026-08-10）
ビルドをアップロードしても「テスト可能なビルド」に出てこない、という状態になった。
原因は**グループ／テスターが未割り当てだっただけ**。
TestFlight → iOSビルド →「ビルドのアップロード」の一覧から**ビルド番号のリンクを開き**、
その画面で `グループ` と `個人テスター` の「+」から追加する。
（グループ側の「+」からビルドを探す導線では出てこないことがある）
※「ビルドのアップロード」欄の**「終了」はアップロード完了の意味**で、配布可能とは別。

### 収益化（保留中）
- **AdSense は2回不承認**。理由はどちらも「コンテンツの量や質」の定型文
  - 記事12ページを追加しても同じ判定 → **`github.io` が共有サブドメインである点が実質的な壁**と判断
  - 次の一手は**独自ドメイン取得**（Cloudflare Registrar で取得する方針だったが未着手）
  - クライアントID `ca-pub-9774452859108904` は設置済み（`ad_config.dart` / 各HTML / ルートの `ads.txt`）
- **AdMob（アプリ内広告）は 2026-08-10 に丸ごと削除した。v1.0 は広告なしで出す**
  - 理由: ①テストIDのまま公開すると実ユーザーに「Test Ad」が表示される状態だった
    ②AdMob未登録で収益はゼロ、③広告SDKがあるとプライバシー申告が複雑になる
  - **戻し方・戻したときに必要な申告の変更は `docs/appstore_privacy.md` §4 に記載**
  - 削除コミット: `git log --oneline --grep="アプリ版の広告"`（revert すれば戻る）

---

## 6. 絶対に踏んではいけない落とし穴（実際に踏んだもの）

### 6-1. Nominatim は Dart 既定の User-Agent を 403 で拒否する
Web はブラウザが自動でヘッダーを付けるため気づかず、**ネイティブでのみ「場所指定検索だけ失敗」**する形で露見した。
`bento_service.dart` の `_apiHeaders`（`kIsWeb` なら空、ネイティブならアプリ識別 UA）で解決済み。
**Web では User-Agent の上書きがブラウザ仕様で禁止**なので送ってはいけない。

### 6-2. Overpass ミラーは「ステータス+速度」で選んではいけない
`overpass.osm.ch` は**スイス限定データ**のため、日本の座標では「200 OK かつ 0件」を 1.9 秒で返す。
これを「最速の優良ミラー」と誤判定して1番目に採用し、**全国で検索0件**の事故を起こした。
→ **必ず日本の座標で「要素数」を確認すること。**
→ 対策として `_hasElements()` を実装済み（200でも0件なら次のミラーを試す）。

現行の順序: `overpass-api.de` → `overpass.kumi.systems` → `maps.mail.ru`（各20秒）
`overpass.private.coffee` は無応答で不採用。

### 6-3. Overpass クエリの「最適化」は逆効果だった
`["shop"]["name"~...]` のようにキーで絞ってから店名照合する形は、
都心部では shop キーを持つ要素が膨大なため**遅くなる**（東京駅1km: 29秒 → 40秒超でタイムアウト）。
現行の `["name"~...]` 単独指定が最善。
なお応答時間は**サーバー混雑で 3.7秒〜29秒と大きく変動**する（クエリ構造の問題ではない）。

### 6-4. `flutter analyze` がビルド生成物を解析して落ちる
iOS ビルド時に `build/ios/SourcePackages/` へ google_mobile_ads のテストコードが展開され、
その解析エラーで CI が失敗した。`analysis_options.yaml` で `build/**` と `ios/Pods/**` を除外済み。

### 6-5. `Uri.base` はネイティブでは file:// を指す
記事リンクに `Uri.base.resolve()` を使っていたため、**iOS でフッターのリンクが無反応**だった。
ネイティブでは公開サイトの絶対URL（`_siteBaseUrl`）を使うよう修正済み。

### 6-6. Claude のブラウザ操作の可否（2026-08-10 更新）
**`appstoreconnect.apple.com` は操作可能**。2026-08-10 に実際にアクセスし、掲載情報の入力・
ビルド選択・プライバシー申告・年齢制限の質問票・配信地域の設定まで Claude が実施した。
以前ここに「操作不可」と書いてあったのは誤り。`developer.apple.com` も操作可能。

**操作できないもの**: `codemagic.io` / `au.com` / `my.au.com`。
また、ドメインの可否とは別に、**パスワード入力と「審査へ提出」のような不可逆な操作は
Claude は行わない**（提出はユーザーの確認のうえ、ユーザーが押す）。

---

## 7. Codemagic（iOSビルド）

- ワークフロー名: **`iOS リリース (TestFlight)`**（`codemagic.yaml` の `ios-release`）
- App Store Connect API キーの統合名: **`bento-navi-asc`**（Settings → Integrations → **Developer Portal**）
- 環境変数グループ: **`appstore`** に `CERTIFICATE_PRIVATE_KEY` を登録（Secure）
  - ⚠️ Codemagic の UI 環境変数は**グループに入れ、yaml の `environment.groups` で参照**しないと読めない
- 署名は `app-store-connect fetch-signing-files --create` 方式
  （自動署名 `ios_signing` は既存プロファイルを探すだけなので初回に失敗する）
- `submit_to_testflight: false`
  （true にすると外部テストの審査提出になり、テスト情報未入力で失敗する。内部テストは審査不要）

### ビルド手順
Codemagic → Applications → bento-navi → **Start new build** → Branch `main` / Workflow `iOS リリース (TestFlight)`
> `codemagic.yaml` は毎回 GitHub から取得されるので、画面側の設定変更は不要。

---

## 8. 秘密情報の在り処（内容はここに書かない）

| もの | 場所 | 備考 |
|---|---|---|
| iOS配布証明書の秘密鍵 | `C:\Users\pw282\Desktop\ios_distribution_private_key` | **紛失すると証明書の作り直し**。安全な場所へ移すこと |
| App Store Connect API キー | `.p8` ファイル（ユーザーが保管） | 再ダウンロード不可 |

---

## 9. ユーザーについて共有すべきこと

- Apple ID の**通知先メールは Gmail**（`excitedcherry0909@gmail.com`）で設定済み
- ただし **Apple ID 自体が `...@ezweb.ne.jp`** の可能性がある。UQ mobile へ乗り換え済みで
  「auメール持ち運び」未申込・31日超過のため、**このアドレスは受信できない**
  → パスワード再設定時のリスクが残るため、Gmail への変更を勧めてある（未確認）

---

## 10. よく使うコマンド

```bash
# 解析・テスト
flutter analyze
flutter test

# Web版のビルドとデプロイ（gh-pages へ force push）
flutter build web --release --base-href /bento-navi/
cd build/web && touch .nojekyll && git init -q && git checkout -q -b gh-pages \
  && git add -A && git commit -q -m "deploy" \
  && git push -f https://github.com/Hammy-the-cat/bento-navi.git gh-pages && rm -rf .git

# アイコンの再生成
python tool/make_icon.py && dart run flutter_launcher_icons

# 掲載原稿の文字数チェック
python tool/check_listing.py
```

> ローカル確認用のプレビューは `.claude/launch.json` の `bento-navi-web`（ポート8791）。

---

## 11. 進め方の方針

- ユーザーは技術者ではないので、**画面のどこを押すかまで具体的に案内する**
- 実機でのバグ報告が的確なので、**まず実測で切り分けてから直す**（推測で修正しない）
- 公共APIの不安定さが残課題。根本対策として
  **Cloudflare Workers でキャッシュを挟む**構成を提案済み（未着手）
