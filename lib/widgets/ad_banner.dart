import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../config/ad_config.dart';
import 'adsense_view_stub.dart'
    if (dart.library.js_interop) 'adsense_view_web.dart';
import 'mobile_ads_stub.dart' if (dart.library.io) 'mobile_ads_impl.dart';

/// 広告バナー。
/// - Web        : AdSense(スロット未設定の間はプレースホルダー)
/// - iOS/Android: AdMob
/// - それ以外    : プレースホルダー
class AdBanner extends StatelessWidget {
  final String slot;
  final double height;

  const AdBanner({super.key, required this.slot, this.height = 100});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: height,
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(child: _adContent(theme)),
          // 広告であることの明示ラベル
          Positioned(
            top: 0,
            left: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: const BorderRadius.only(
                  bottomRight: Radius.circular(8),
                ),
              ),
              child: Text('スポンサー',
                  style: TextStyle(
                      fontSize: 9,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  /// プラットフォームに応じて表示する広告を選ぶ
  Widget _adContent(ThemeData theme) {
    if (kIsWeb) {
      return AdConfig.adsenseEnabled
          ? buildAdsenseView(AdConfig.adsenseClient, slot, height)
          : _placeholder(theme);
    }
    // モバイルはAdMob。非対応環境(デスクトップ等)ではnullが返る
    return buildAdmobBanner(height) ?? _placeholder(theme);
  }

  Widget _placeholder(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.storefront_outlined,
              color: Colors.grey.shade300, size: 28),
          const SizedBox(height: 4),
          Text('広告スペース',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
          Text('(公開・AdSense審査後に配信されます)',
              style: TextStyle(fontSize: 9, color: Colors.grey.shade400)),
        ],
      ),
    );
  }
}
