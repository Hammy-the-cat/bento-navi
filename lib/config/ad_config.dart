/// 広告(Google AdSense)の設定。
///
/// 収益化の手順:
/// 1. アプリを独自ドメインで公開する(例: GitHub Pages + 独自ドメイン、Cloudflare Pagesなど)
/// 2. https://adsense.google.com でサイトを登録し審査を通す
/// 3. 審査通過後、発行された「ca-pub-」で始まるクライアントIDと
///    広告ユニットのスロットIDを下に貼り付けて再ビルドする
///
/// IDが未設定の間は、実広告の代わりにプレースホルダーが表示される。
class AdConfig {
  /// AdSenseのクライアントID (例: 'ca-pub-1234567890123456')
  static const String adsenseClient = 'ca-pub-XXXXXXXXXXXXXXXX';

  /// 検索中(ローディング)画面に出す広告ユニットのスロットID
  static const String slotLoading = '0000000000';

  /// 検索結果リストの途中に出す広告ユニットのスロットID
  static const String slotInFeed = '0000000001';

  /// リスト内広告を何件ごとに挟むか
  static const int inFeedInterval = 5;

  /// IDが本物に差し替えられていれば true
  static bool get enabled => !adsenseClient.contains('X');
}
