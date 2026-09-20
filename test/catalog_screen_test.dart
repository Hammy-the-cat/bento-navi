import 'package:bento_navi/models/catalog_shop.dart';
import 'package:bento_navi/screens/catalog_screen.dart';
import 'package:bento_navi/services/bento_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('全掲載地域と所在地未確認店舗もカタログに残る', () async {
    final service = BentoService();
    addTearDown(service.dispose);
    final catalog = await service.loadCatalog();
    expect(catalog.length, 11022);
    expect(catalog.map((s) => s.id).toSet().length, catalog.length);
    expect(catalog.map((s) => s.prefecture).toSet().length, 38);
    expect(catalog.where((s) => !s.hasLocation).length, 7);
    expect(catalog.any((s) => s.id == 'MYZ-0062'), isFalse);
    expect(
      catalog.firstWhere((s) => s.id == 'MYZ-0444').matches('宮崎 甘雨'),
      isTrue,
    );
    final nearby = await service.searchCuratedShops(
      31.4631,
      131.2285,
      radiusMeters: 10000,
    );
    expect(nearby, isNotEmpty);
    expect(nearby.any((s) => s.name == '甘雨'), isFalse);
  });

  testWidgets('住所非公開店を探せて誤った地図ボタンを出さない', (tester) async {
    final shops = [
      CatalogShop.fromJson({
        'id': 'A',
        'name': '甘雨',
        'prefecture': '宮崎県',
        'municipality': '串間市',
        'coordinateAccuracy': '対象外（販売店舗なし）',
        'sourceUrl': 'https://www.instagram.com/kanu040122/',
      }),
      CatalogShop.fromJson({
        'id': 'B',
        'name': '別のお店',
        'prefecture': '福岡県',
        'municipality': '福岡市',
        'lat': 33.5,
        'lon': 130.4,
      }),
    ];
    await tester.pumpWidget(
      MaterialApp(home: CatalogScreen(loadCatalog: () async => shops)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '串間 甘雨');
    await tester.pumpAndSettle();
    expect(find.text('別のお店'), findsNothing);
    await tester.tap(find.text('甘雨'));
    await tester.pumpAndSettle();
    expect(find.text('店舗の案内'), findsOneWidget);
    expect(find.text('地図'), findsNothing);
    expect(find.textContaining('販売店舗なし'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
