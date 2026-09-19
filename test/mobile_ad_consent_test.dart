import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:bento_navi/services/mobile_ad_consent.dart';
import 'package:bento_navi/widgets/mobile_banner.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class FakeConsent extends AdConsentGateway {
  bool allowed = false;
  bool fail = false;
  int initializations = 0;
  @override
  Future<void> gather() async {
    if (fail) throw Exception('offline');
  }

  @override
  Future<bool> canRequestAds() async => allowed;
  @override
  Future<bool> privacyOptionsRequired() async => true;
  @override
  Future<void> showPrivacyOptions() async {
    allowed = false;
  }

  @override
  Future<void> initializeAds() async {
    initializations++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('ネイティブの同意変更エラーを呼び出し元で捕捉できる', () async {
    const channel = MethodChannel('plugins.flutter.io/google_mobile_ads/ump');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: '1', message: 'offline');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await expectLater(
        GoogleConsentGateway().showPrivacyOptions(), throwsA(isA<FormError>()));
  });
  test('同意確認で許可されない場合はSDKを初期化しない', () async {
    final fake = FakeConsent();
    final consent = MobileAdConsent(fake);
    await consent.start();
    expect(consent.canShowAds, false);
    expect(fake.initializations, 0);
    expect(consent.privacyOptionsRequired, true);
  });
  test('許可後のみ初期化し、再呼び出しで重複しない', () async {
    final fake = FakeConsent()..allowed = true;
    final consent = MobileAdConsent(fake);
    await consent.start();
    await consent.start();
    expect(consent.canShowAds, true);
    expect(fake.initializations, 1);
    await consent.showPrivacyOptions();
    expect(consent.canShowAds, false);
    expect(fake.initializations, 1);
  });
  test('初回の通信エラーでは広告を出さず再試行できる', () async {
    final fake = FakeConsent()..fail = true;
    final consent = MobileAdConsent(fake);
    await consent.start();
    expect(consent.failed, true);
    expect(consent.canShowAds, false);
    fake
      ..fail = false
      ..allowed = true;
    await consent.retry();
    expect(consent.failed, false);
    expect(consent.canShowAds, true);
  });
}
