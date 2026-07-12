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
}
