import 'package:flutter_test/flutter_test.dart';

import 'package:bento_navi/services/bento_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('調査済み店舗データから串間市の店舗を検索できる', () async {
    final service = BentoService();
    final shops = await service.searchCuratedShops(
      31.4631,
      131.2285,
      radiusMeters: 10000,
    );

    expect(shops.length, greaterThanOrEqualTo(20));
    expect(shops.any((shop) => shop.name == 'だいぐち弁当'), isTrue);
    expect(shops.any((shop) => shop.name == '寿司虎 串間本店'), isTrue);
    expect(shops.every((shop) => shop.isCurated), isTrue);
  });

  test('調査済み店舗データからえびの市の店舗を検索できる', () async {
    final service = BentoService();
    final shops = await service.searchCuratedShops(
      32.0474,
      130.8118,
      radiusMeters: 20000,
    );

    expect(shops.length, greaterThanOrEqualTo(15));
    expect(shops.any((shop) => shop.name == '居心家GEN'), isTrue);
    expect(shops.any((shop) => shop.name == '総合仕出し 大太鼓'), isTrue);
    expect(shops.any((shop) => shop.name == 'えびのPA下り スナックコーナー'), isTrue);
  });
}
