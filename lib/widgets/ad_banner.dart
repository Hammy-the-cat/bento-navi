import 'package:flutter/material.dart';

import '../config/ad_config.dart';
import 'adsense_view_stub.dart'
    if (dart.library.html) 'adsense_view_web.dart';

/// 広告バナー。
/// AdSenseのIDが設定済み(かつWeb)なら実広告を、
/// 未設定ならプレースホルダーを表示する。
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
          Positioned.fill(
            child: AdConfig.enabled
                ? buildAdsenseView(AdConfig.adsenseClient, slot, height)
                : _placeholder(theme),
          ),
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
