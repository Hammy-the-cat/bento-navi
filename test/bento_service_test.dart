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
    final yorimichi = kochi.firstWhere((shop) => shop.name == 'よりみちキッチン');
    expect(yorimichi.sourceUrl, contains('instagram.com/yorimichi_kitchen'));
    expect(yorimichi.isCurated, isTrue);
  });

  test('中国地方5県の追加店舗を検索できる', () async {
    final service = BentoService();

    final tottori = await service.searchCuratedShops(
      35.553734,
      134.363235,
      radiusMeters: 500,
    );
    final ogura = tottori.firstWhere((shop) => shop.name == '仕出し弁当 おぐら');
    expect(ogura.phone, '0857-73-0308');
    expect(ogura.notes, contains('配達対応'));

    final shimane = await service.searchCuratedShops(
      36.096966,
      133.109116,
      radiusMeters: 500,
    );
    final uchiNoGohan = shimane.firstWhere((shop) => shop.name == 'うちのごはん');
    expect(uchiNoGohan.sourceUrl, contains('ama-town.note.jp'));

    final okayama = await service.searchCuratedShops(
      34.958153,
      133.875092,
      radiusMeters: 500,
    );
    final chezNous =
        okayama.firstWhere((shop) => shop.name == 'CHEZ NOUS（シェヌー）');
    expect(chezNous.phone, '070-4295-4778');

    final hiroshima = await service.searchCuratedShops(
      34.365327,
      132.362680,
      radiusMeters: 500,
    );
    expect(
      hiroshima.any((shop) => shop.name == 'ほっともっと 佐伯区役所前店'),
      isTrue,
    );

    final yamaguchi = await service.searchCuratedShops(
      33.978559,
      130.941833,
      radiusMeters: 500,
    );
    expect(
      yamaguchi.any((shop) => shop.name == 'ほっともっと 下関宝町店'),
      isTrue,
    );
  });

  test('近畿地方のInstagram追加店舗を検索できる', () async {
    final service = BentoService();

    final mie = await service.searchCuratedShops(
      34.581635,
      136.621979,
      radiusMeters: 500,
    );
    final hane = mie.firstWhere((shop) => shop.name == 'Hane');
    expect(hane.phone, '070-2332-5289');
    expect(hane.sourceUrl, contains('instagram.com/hane.38'));

    final shiga = await service.searchCuratedShops(
      35.194054,
      136.294937,
      radiusMeters: 500,
    );
    final ootaki = shiga.firstWhere((shop) => shop.name == 'おおたき給食弁当');
    expect(ootaki.notes, contains('地域内配達あり'));

    final kyoto = await service.searchCuratedShops(
      34.780128,
      135.788971,
      radiusMeters: 500,
    );
    final okkamotto = kyoto.firstWhere((shop) => shop.name == 'おっかもっと');
    expect(okkamotto.notes, contains('配達可'));

    final osaka = await service.searchCuratedShops(
      34.391262,
      135.290619,
      radiusMeters: 500,
    );
    final takesKitchen =
        osaka.firstWhere((shop) => shop.name == "Take's kitchen");
    expect(takesKitchen.phone, '080-1502-2840');

    final nara = await service.searchCuratedShops(
      34.241943,
      135.855270,
      radiusMeters: 500,
    );
    expect(
      nara.any((shop) => shop.name == 'おむすび＆Cafe 喫茶みつば'),
      isTrue,
    );

    final wakayama = await service.searchCuratedShops(
      33.958530,
      135.937027,
      radiusMeters: 500,
    );
    final gotencho = wakayama.firstWhere((shop) => shop.name == 'ごてんちょキッチン');
    expect(gotencho.notes, contains('予約制'));
    expect(gotencho.isCurated, isTrue);
  });

  test('東北6県の追加店舗を検索できる', () async {
    final service = BentoService();
    final cases = <Map<String, Object>>[
      {
        'name': '間木ノ平グリーンパーク',
        'lat': 40.453327,
        'lon': 141.112885,
        'phone': '0178-78-3333',
      },
      {
        'name': '鯛寿司',
        'lat': 39.930553,
        'lon': 141.917175,
        'phone': '0194-34-2702',
      },
      {
        'name': 'Cafe Bridge',
        'lat': 38.468071,
        'lon': 140.852112,
        'phone': '022-342-1677',
      },
      {
        'name': '井川さくらキッチン',
        'lat': 39.908676,
        'lon': 140.087769,
        'phone': '018-855-6170',
      },
      {
        'name': 'お惣菜とお食事の店 ヤマキチ',
        'lat': 38.294468,
        'lon': 140.269531,
        'phone': '023-664-5620',
      },
      {
        'name': 'レストラン エフ',
        'lat': 37.458084,
        'lon': 141.030746,
        'phone': '080-5842-2640',
      },
    ];

    for (final testCase in cases) {
      final shops = await service.searchCuratedShops(
        testCase['lat']! as double,
        testCase['lon']! as double,
        radiusMeters: 300,
      );
      final shop = shops.firstWhere(
        (candidate) => candidate.name == testCase['name'],
      );
      expect(shop.phone, testCase['phone']);
      expect(shop.sourceUrl, isNotEmpty);
      expect(shop.isCurated, isTrue);
    }
  });

  test('中部9県の追加店舗を検索できる', () async {
    final service = BentoService();
    final cases = <Map<String, Object>>[
      {
        'name': 'しげよし町田本店',
        'lat': 37.952557,
        'lon': 139.241013,
        'phone': '050-3196-5088',
      },
      {
        'name': 'お※食堂',
        'lat': 36.705845,
        'lon': 137.306183,
        'phone': '076-464-5272',
      },
      {
        'name': '食べ処オアシス',
        'lat': 36.469639,
        'lon': 136.541122,
        'phone': '076-277-0065',
      },
      {
        'name': 'まちの駅 こってコテいけだ',
        'lat': 35.887623,
        'lon': 136.345261,
        'phone': '0778-44-8050',
      },
      {
        'name': '宅配弁当 円',
        'lat': 35.600006,
        'lon': 138.521927,
        'phone': '055-274-3991',
      },
      {
        'name': 'レストラン ストローハット',
        'lat': 35.993179,
        'lon': 138.442673,
        'phone': '0267-96-2445',
      },
      {
        'name': '日本料理 郷部',
        'lat': 35.433296,
        'lon': 136.987595,
        'phone': '0574-26-8286',
      },
      {
        'name': 'さくらの宿 一膳',
        'lat': 34.771152,
        'lon': 138.960876,
        'phone': '0558-36-3606',
      },
      {
        'name': 'レストラン山河',
        'lat': 35.099102,
        'lon': 137.572281,
        'phone': '0536-62-2132',
      },
    ];

    for (final testCase in cases) {
      final shops = await service.searchCuratedShops(
        testCase['lat']! as double,
        testCase['lon']! as double,
        radiusMeters: 300,
      );
      final shop = shops.firstWhere(
        (candidate) => candidate.name == testCase['name'],
      );
      expect(shop.phone, testCase['phone']);
      expect(shop.sourceUrl, isNotEmpty);
      expect(shop.isCurated, isTrue);
    }
  });

  test('北海道の追加店舗を検索できる', () async {
    final service = BentoService();
    final cases = <Map<String, Object>>[
      {
        'name': 'すずめキッチン',
        'lat': 44.293587,
        'lon': 142.615723,
        'phone': '090-8238-8073',
      },
      {
        'name': 'レストラン矢野（温泉旅館矢野）',
        'lat': 41.431828,
        'lon': 140.111603,
        'phone': '0139-42-2525',
      },
      {
        'name': '有限会社 仕出し屋 はちや',
        'lat': 43.980492,
        'lon': 145.141037,
        'phone': '090-3398-3866',
      },
      {
        'name': '浜田旅館',
        'lat': 43.521431,
        'lon': 143.784958,
        'phone': '0156-27-3175',
      },
    ];

    for (final testCase in cases) {
      final shops = await service.searchCuratedShops(
        testCase['lat']! as double,
        testCase['lon']! as double,
        radiusMeters: 300,
      );
      final shop = shops.firstWhere(
        (candidate) => candidate.name == testCase['name'],
      );
      expect(shop.phone, testCase['phone']);
      expect(shop.sourceUrl, isNotEmpty);
      expect(shop.isCurated, isTrue);
    }
  });
}
