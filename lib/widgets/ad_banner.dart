import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../config/ad_config.dart';
import 'adsense_view_stub.dart'
    if (dart.library.js_interop) 'adsense_view_web.dart';

/// 広告バナー。
/// - Web        : AdSense(スロット未設定の間はプレースホルダー)
/// - アプリ版    : 何も表示しない(v1.0では広告を載せていないため、
///                空の枠だけが残らないようウィジェットごと消す)
class AdBanner extends StatelessWidget {
  final String slot;
  final double height;

  const AdBanner({super.key, required this.slot, this.height = 100});

  @override
  Widget build(BuildContext context) {
    // アプリ版(iOS/Android)は広告なし。枠も出さない。
    if (!kIsWeb) return const SizedBox.shrink();

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

  /// Web版の広告。スロット未作成の間はプレースホルダー
  Widget _adContent(ThemeData theme) {
    return AdConfig.adsenseEnabled
        ? buildAdsenseView(AdConfig.adsenseClient, slot, height)
        : _placeholder(theme);
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
