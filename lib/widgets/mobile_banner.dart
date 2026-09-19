import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/mobile_ad_consent.dart';

// Explicit opt-in only. Store builds must never default to test ads.
const _adMode = String.fromEnvironment('MOBILE_ADS_MODE', defaultValue: 'off');
const _productionUnit = String.fromEnvironment('ADMOB_IOS_BANNER_ID');
bool get mobileAdsEnabled =>
    !kIsWeb &&
    defaultTargetPlatform == TargetPlatform.iOS &&
    (_adMode == 'test' ||
        (_adMode == 'production' &&
            RegExp(r'^ca-app-pub-\d{16}/\d{10}$').hasMatch(_productionUnit) &&
            !_productionUnit.startsWith('ca-app-pub-3940256099942544/')));

class GoogleConsentGateway implements AdConsentGateway {
  @override
  Future<void> gather() {
    final done = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () async {
        try {
          await ConsentForm.loadAndShowConsentFormIfRequired((error) {
            if (done.isCompleted) return;
            if (error == null) {
              done.complete();
            } else {
              done.completeError(error);
            }
          });
        } catch (error) {
          if (!done.isCompleted) done.completeError(error);
        }
      },
      (error) {
        if (!done.isCompleted) done.completeError(error);
      },
    );
    return done.future;
  }

  @override
  Future<bool> canRequestAds() => ConsentInformation.instance.canRequestAds();
  @override
  Future<bool> privacyOptionsRequired() async =>
      await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() ==
      PrivacyOptionsRequirementStatus.required;
  @override
  Future<void> showPrivacyOptions() async {
    final done = Completer<void>();
    await ConsentForm.showPrivacyOptionsForm((error) {
      if (error == null) {
        done.complete();
      } else {
        done.completeError(error);
      }
    });
    await done.future;
  }

  @override
  Future<void> initializeAds() async {
    await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(maxAdContentRating: MaxAdContentRating.g));
    await MobileAds.instance.initialize();
  }
}

final mobileAdConsent = MobileAdConsent(GoogleConsentGateway());

class MobileAdPrivacyButton extends StatelessWidget {
  const MobileAdPrivacyButton({super.key});
  @override
  Widget build(BuildContext context) {
    if (!mobileAdsEnabled) return const SizedBox.shrink();
    return ListenableBuilder(
        listenable: mobileAdConsent,
        builder: (context, _) {
          if (mobileAdConsent.privacyOptionsRequired) {
            return TextButton(
                onPressed: mobileAdConsent.busy
                    ? null
                    : mobileAdConsent.showPrivacyOptions,
                child: const Text('広告のプライバシー設定'));
          }
          if (mobileAdConsent.failed) {
            return TextButton(
                onPressed: mobileAdConsent.busy ? null : mobileAdConsent.retry,
                child: const Text('広告の同意設定を再確認'));
          }
          return const SizedBox.shrink();
        });
  }
}

class MobileSearchBanner extends StatelessWidget {
  const MobileSearchBanner({super.key});
  @override
  Widget build(BuildContext context) {
    if (!mobileAdsEnabled) return const SizedBox.shrink();
    return ListenableBuilder(
        listenable: mobileAdConsent,
        builder: (context, _) => mobileAdConsent.canShowAds
            ? const _LoadedBanner()
            : const SizedBox.shrink());
  }
}

class _LoadedBanner extends StatefulWidget {
  const _LoadedBanner();
  @override
  State<_LoadedBanner> createState() => _LoadedBannerState();
}

class _LoadedBannerState extends State<_LoadedBanner> {
  BannerAd? _ad;
  bool _loaded = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ad = BannerAd(
      adUnitId: _adMode == 'test'
          ? 'ca-app-pub-3940256099942544/2435281174'
          : _productionUnit,
      size: AdSize.banner,
      request: const AdRequest(nonPersonalizedAds: true),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted && identical(ad, _ad)) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          if (!identical(ad, _ad)) return;
          _ad = null;
          ad.dispose();
          if (mounted) setState(() => _loaded = false);
        },
      ),
    );
    _ad = ad;
    try {
      await ad.load();
    } catch (_) {
      if (identical(_ad, ad)) {
        _ad = null;
        ad.dispose();
      }
      if (mounted) setState(() => _loaded = false);
    }
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _ad == null || MediaQuery.sizeOf(context).width < 320) {
      return const SizedBox.shrink();
    }
    return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_adMode == 'test' ? '広告（テスト）' : '広告',
                style: const TextStyle(fontSize: 10)),
            const SizedBox(height: 6),
            SizedBox(width: 320, height: 50, child: AdWidget(ad: _ad!)),
          ]),
        ));
  }
}
