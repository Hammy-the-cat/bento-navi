import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../config/ad_config.dart';

/// Android/iOS向けのAdMob実装。
/// (Windows等のデスクトップではAdMob非対応のためnullを返す)

bool get _isSupported => Platform.isAndroid || Platform.isIOS;

/// モバイル広告SDKの初期化。main()から呼ぶ。
Future<void> initMobileAds() async {
  if (!_isSupported) return;
  try {
    await MobileAds.instance.initialize();
  } catch (_) {
    // 初期化に失敗しても、アプリ本体の機能には影響させない
  }
}

/// AdMobバナーを返す。非対応環境ではnull。
Widget? buildAdmobBanner(double height) {
  if (!_isSupported) return null;
  return _AdmobBanner(height: height);
}

class _AdmobBanner extends StatefulWidget {
  final double height;
  const _AdmobBanner({required this.height});

  @override
  State<_AdmobBanner> createState() => _AdmobBannerState();
}

class _AdmobBannerState extends State<_AdmobBanner> {
  BannerAd? _ad;
  bool _loaded = false;

  /// 枠の高さに合わせた広告サイズを選ぶ
  AdSize get _adSize {
    if (widget.height >= 200) return AdSize.mediumRectangle; // 300x250
    if (widget.height >= 90) return AdSize.largeBanner; // 320x100
    return AdSize.banner; // 320x50
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final ad = BannerAd(
      adUnitId: AdConfig.admobBannerUnitId(isIOS: Platform.isIOS),
      size: _adSize,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          debugPrint('AdMob load failed: $error');
        },
      ),
    );
    _ad = ad;
    ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    // 読み込み完了までは何も表示しない(枠だけ残る)
    if (ad == null || !_loaded) return const SizedBox.shrink();
    return Center(
      child: SizedBox(
        width: ad.size.width.toDouble(),
        height: ad.size.height.toDouble(),
        child: AdWidget(ad: ad),
      ),
    );
  }
}
