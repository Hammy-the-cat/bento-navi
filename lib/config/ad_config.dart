/// 広告の設定。
///
/// Web版のGoogle AdSense設定。
/// iOSのAdMob設定は mobile_banner.dart と docs/広告導入状況.md を参照。
///
/// スロットIDが未設定の間は、実広告の代わりにプレースホルダーが表示される。
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

  // ───────── 共通 ─────────

  /// リスト内広告を何件ごとに挟むか
  static const int inFeedInterval = 5;
}
