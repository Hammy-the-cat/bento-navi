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

  test('追加した日向市の店舗情報を検索結果へ反映できる', () async {
    final service = BentoService();
    final shops = await service.searchCuratedShops(
      32.4236,
      131.6343,
      radiusMeters: 3000,
    );

    expect(shops.any((shop) => shop.name == 'だいずきっちん'), isTrue);
    expect(shops.any((shop) => shop.name == 'お弁当屋さん ま結'), isTrue);
    final deliveryShop = shops.firstWhere((shop) => shop.name == 'お弁当屋さん ま結');
    expect(deliveryShop.phone, '070-2166-1158');
    expect(deliveryShop.notes, contains('配達対応'));
  });

  test('追加した都城市の店舗情報を検索結果へ反映できる', () async {
    final service = BentoService();
    final shops = await service.searchCuratedShops(
      31.7313,
      131.0692,
      radiusMeters: 6000,
    );

    expect(shops.any((shop) => shop.name == 'tanbo.'), isTrue);
    expect(shops.any((shop) => shop.name == '居食館 南都乃風 牟田町店'), isTrue);
    expect(
      shops.firstWhere((shop) => shop.name == 'tanbo.').notes,
      contains('配達料500円'),
    );
  });

  test('鹿児島県の店舗情報を電話・配達メモ付きで検索できる', () async {
    final service = BentoService();
    final shops = await service.searchCuratedShops(
      31.579859,
      130.552795,
      radiusMeters: 3000,
    );

    final shop = shops.firstWhere((shop) => shop.name == '薩摩仕出し料理 典座');
    expect(shop.phone, '099-253-3130');
    expect(shop.notes, contains('配達'));
    expect(shop.isCurated, isTrue);
  });

  test('大分県の最新追加店舗を検索できる', () async {
    final service = BentoService();
    final shops = await service.searchCuratedShops(
      33.541992,
      131.570496,
      radiusMeters: 3000,
    );

    final shop = shops.firstWhere((shop) => shop.name == 'まめのもんや');
    expect(shop.phone, '090-7396-9339');
    expect(shop.notes, contains('配達'));
    expect(shop.isCurated, isTrue);
  });

  test('長崎県の店舗情報を検索できる', () async {
    final service = BentoService();
    final shops = await service.searchCuratedShops(
      32.783558,
      129.869370,
      radiusMeters: 1000,
    );

    final shop = shops.firstWhere((shop) => shop.name == 'お弁当のぐ～');
    expect(shop.phone, '095-844-7078');
    expect(shop.notes, contains('配達'));
    expect(shop.isCurated, isTrue);
  });

  test('佐賀県のInstagram追加店舗を検索できる', () async {
    final service = BentoService();
    final shops = await service.searchCuratedShops(
      33.240166,
      130.288803,
      radiusMeters: 1000,
    );

    final shop = shops.firstWhere((shop) => shop.name == 'マハトマ');
    expect(shop.phone, '0952-97-8533');
    expect(shop.sourceUrl, contains('instagram.com/mahatma978533'));
    expect(shop.isCurated, isTrue);
  });

  test('福岡県の店舗情報を電話・配達メモ付きで検索できる', () async {
    final service = BentoService();
    final shops = await service.searchCuratedShops(
      33.556374,
      130.464630,
      radiusMeters: 1000,
    );

    final shop = shops.firstWhere((shop) => shop.name == 'はがくれ弁当 福岡本店');
    expect(shop.phone, '092-502-8070');
    expect(shop.notes, contains('配達'));
    expect(shop.sourceUrl, 'https://hagakure-b.co.jp/area/');
    expect(shop.isCurated, isTrue);
  });

  test('四国4県のInstagram追加店舗を検索できる', () async {
    final service = BentoService();

    final tokushima = await service.searchCuratedShops(
      34.047276,
      134.575150,
      radiusMeters: 500,
    );
    final lakiBento =
        tokushima.firstWhere((shop) => shop.name == 'lakiBENTO（ラキ弁当）');
    expect(lakiBento.phone, '088-635-1913');
    expect(lakiBento.sourceUrl, contains('instagram.com/lakibento'));

    final kagawa = await service.searchCuratedShops(
      34.143593,
      133.692917,
      radiusMeters: 500,
    );
    final muku = kagawa.firstWhere((shop) => shop.name == 'むく食堂');
    expect(muku.phone, '070-1226-1151');
    expect(muku.notes, contains('事前予約'));

    final ehime = await service.searchCuratedShops(
      33.918674,
      133.166107,
      radiusMeters: 500,
    );
    final nabento = ehime.firstWhere((shop) => shop.name == 'nabento');
    expect(nabento.notes, contains('5個以上で配達'));
    expect(nabento.sourceUrl, contains('instagram.com/_nabento'));

    final kochi = await service.searchCuratedShops(
      33.500835,
      133.286713,
      radiusMeters: 500,
    );
    final yorimichi =
        kochi.firstWhere((shop) => shop.name == 'よりみちキッチン');
    expect(yorimichi.sourceUrl, contains('instagram.com/yorimichi_kitchen'));
    expect(yorimichi.isCurated, isTrue);
  });
}
