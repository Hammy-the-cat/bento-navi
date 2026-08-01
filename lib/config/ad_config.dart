/// 広告の設定。
///
/// プラットフォームで使う広告サービスが異なる:
///   - Web        → Google AdSense (ca-pub-...)
///   - iOS/Android → Google AdMob   (ca-app-pub-...)
///
/// IDが未設定・テスト用の間は、実広告の代わりに
/// プレースホルダー(またはテスト広告)が表示される。
class AdConfig {
  // ───────── Web: AdSense ─────────

  /// AdSenseのクライアントID
  static const String adsenseClient = 'ca-pub-9774452859108904';

  /// 検索中(ローディング)画面に出す広告ユニットのスロットID
  /// (審査通過後にAdSenseで「ディスプレイ広告」ユニットを作成して差し替える)
  static const String slotLoading = '0000000000';

  /// 検索結果リストの途中に出す広告ユニットのスロットID
  static const String slotInFeed = '0000000001';

  /// AdSenseの実配信が可能か(スロット未作成の間はプレースホルダー)
  static bool get adsenseEnabled =>
      !adsenseClient.contains('X') && slotLoading != '0000000000';

  // ───────── モバイル: AdMob ─────────
  //
  // 現在はGoogle公式の「テスト用」広告ユニットID。
  // このままでもテスト広告が表示されるので、開発・ストア審査提出に使える。
  //
  // 収益化の手順:
  //   1. https://admob.google.com でアプリを登録
  //   2. 「バナー」広告ユニットを作成し、発行されたIDを下に貼る
  //   3. アプリIDを ios/Runner/Info.plist の GADApplicationIdentifier と
  //      android/app/src/main/AndroidManifest.xml のメタデータにも設定
  //
  // ※自分で実広告をタップすると規約違反(アカウント停止)になるため、
  //   動作確認は必ずテストIDのまま行うこと。

  /// AdMobバナー広告ユニットID(Android・テスト用)
  static const String admobBannerAndroid =
      'ca-app-pub-3940256099942544/6300978111';

  /// AdMobバナー広告ユニットID(iOS・テスト用)
  static const String admobBannerIos =
      'ca-app-pub-3940256099942544/2934735716';

  /// プラットフォームに応じたバナー広告ユニットIDを返す
  static String admobBannerUnitId({required bool isIOS}) =>
      isIOS ? admobBannerIos : admobBannerAndroid;

  /// テスト用IDのままかどうか(実IDに差し替えたらfalseになる)
  static bool get admobUsingTestIds =>
      admobBannerAndroid.contains('3940256099942544');

  // ───────── 共通 ─────────

  /// リスト内広告を何件ごとに挟むか
  static const int inFeedInterval = 5;
}
