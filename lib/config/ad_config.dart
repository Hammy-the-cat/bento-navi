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
  /// AdSenseのクライアントID
  static const String adsenseClient = 'ca-pub-9774452859108904';

  /// 検索中(ローディング)画面に出す広告ユニットのスロットID
  /// (審査通過後にAdSenseで「ディスプレイ広告」ユニットを作成して差し替える)
  static const String slotLoading = '0000000000';

  /// 検索結果リストの途中に出す広告ユニットのスロットID
  /// (審査通過後にAdSenseで広告ユニットを作成して差し替える)
  static const String slotInFeed = '0000000001';

  /// リスト内広告を何件ごとに挟むか
  static const int inFeedInterval = 5;

  /// クライアントIDとスロットIDの両方が本物に差し替えられていれば true。
  /// スロット未作成の間はプレースホルダーを表示する。
  static bool get enabled =>
      !adsenseClient.contains('X') && slotLoading != '0000000000';
}
