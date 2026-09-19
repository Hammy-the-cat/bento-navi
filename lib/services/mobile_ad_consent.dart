import 'package:flutter/foundation.dart';

/// Kept injectable so consent failures can be tested without contacting Google.
abstract class AdConsentGateway {
  Future<void> gather();
  Future<bool> canRequestAds();
  Future<bool> privacyOptionsRequired();
  Future<void> showPrivacyOptions();
  Future<void> initializeAds();
}

class MobileAdConsent extends ChangeNotifier {
  MobileAdConsent(this.gateway);
  final AdConsentGateway gateway;
  bool canShowAds = false;
  bool privacyOptionsRequired = false;
  bool busy = false;
  bool failed = false;
  bool _initialized = false;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _update(gateway.gather);
  }

  Future<void> showPrivacyOptions() async {
    if (busy) return;
    await _update(gateway.showPrivacyOptions);
  }

  Future<void> retry() async {
    if (busy) return;
    await _update(gateway.gather);
  }

  Future<void> _update(Future<void> Function() action) async {
    busy = true;
    failed = false;
    canShowAds = false;
    notifyListeners();
    try {
      await action();
    } catch (_) {
      failed = true;
    }
    try {
      privacyOptionsRequired = await gateway.privacyOptionsRequired();
      final allowed = await gateway.canRequestAds();
      if (allowed && !_initialized) {
        await gateway.initializeAds();
        _initialized = true;
      }
      canShowAds = allowed && _initialized;
    } catch (_) {
      failed = true;
      canShowAds = false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
