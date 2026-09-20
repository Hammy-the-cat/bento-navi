import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bento_navi/services/bento_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('通信完了前に調査済み店舗を返し、再検索は通信しない', () async {
    final response = Completer<http.Response>();
    final initial = Completer<void>();
    var requests = 0;
    final service = BentoService(
      client: MockClient((request) {
        requests++;
        return response.future;
      }),
    );
    addTearDown(service.dispose);
    var completed = false;
    final search = service.searchShops(
      31.4631,
      131.2285,
      radiusMeters: 10000,
      onInitialResults: (shops) {
        expect(shops, isNotEmpty);
        expect(shops.every((shop) => shop.isCurated), isTrue);
        initial.complete();
      },
    ).then((shops) {
      completed = true;
      return shops;
    });
    await initial.future;
    expect(completed, isFalse);
    response.complete(http.Response('{"elements":[]}', 200));
    final shops = await search;
    final cached = await service.searchShops(
      31.4631,
      131.2285,
      radiusMeters: 10000,
    );
    expect(cached.length, shops.length);
    expect(requests, 1);
    final smaller =
        await service.searchShops(31.4631, 131.2285, radiusMeters: 500);
    expect(requests, 1);
    expect(smaller.every((shop) => shop.distanceMeters <= 500), isTrue);
  });

  test('外部検索が失敗しても調査済み店舗を維持する', () async {
    final service = BentoService(
      client: MockClient((_) async => http.Response('unavailable', 503)),
    );
    addTearDown(service.dispose);
    final shops = await service.searchShops(
      31.4631,
      131.2285,
      radiusMeters: 10000,
    );
    expect(shops, isNotEmpty);
  });

  test('報告された3会場をオフラインで正しい地域へ解決する', () async {
    final service =
        BentoService(client: MockClient((_) => throw StateError('通信不要')));
    addTearDown(service.dispose);
    for (final item in [
      ['帯山中学校　熊本', '熊本市', 32.8013096],
      ['アイビースタジアム　宮崎', '宮崎市', 31.9434282],
      ['市場中学校　神奈川', '横浜市', 35.5148082],
    ]) {
      final places = await service.geocode(item[0] as String);
      expect(places, hasLength(1));
      expect(places.single.displayName, contains(item[1]));
      expect(places.single.lat, item[2]);
    }
  });

  test('不正な200応答とtimeout remarkを0件として保存しない', () async {
    var calls = 0;
    final service = BentoService(client: MockClient((_) async {
      calls++;
      return http.Response(
          '{"elements":[],"remark":"runtime error: timeout"}', 200);
    }));
    addTearDown(service.dispose);
    // 熊本は登録済み店舗なし。失敗は0件ではなくエラー。
    await expectLater(
        service.searchShops(32.8013096, 130.7443793, radiusMeters: 3000),
        throwsException);
    await expectLater(
        service.searchShops(32.8013096, 130.7443793, radiusMeters: 3000),
        throwsException);
    expect(calls, 4);
  });

  test('無応答でも時間を区切り登録店舗と注意表示を返す', () async {
    final service = BentoService(
      client: MockClient((_) => Completer<http.Response>().future),
      proxyTimeout: const Duration(milliseconds: 40),
      fallbackTimeout: const Duration(milliseconds: 40),
    );
    addTearDown(service.dispose);
    String? notice;
    final result = await service
        .searchShops(31.9434282, 131.3716193,
            radiusMeters: 3000, onNotice: (value) => notice = value)
        .timeout(const Duration(seconds: 3));
    expect(result, isNotEmpty);
    expect(notice, contains('登録済み店舗'));
  });

  test('同名の別支店を維持し半径外・不正な店舗は除外する', () async {
    final service = BentoService(
        client: MockClient((_) async => http.Response(
            '''
      {"elements":[
      {"lat":32.801,"lon":130.744,"tags":{"name":"コンビニ","shop":"convenience"}},
      {"lat":32.811,"lon":130.744,"tags":{"name":"コンビニ","shop":"convenience"}},
      {"lat":33.0,"lon":130.744,"tags":{"name":"範囲外"}},
      {"tags":"壊れた要素"}]}
      ''',
            200,
            headers: {'content-type': 'application/json; charset=utf-8'})));
    addTearDown(service.dispose);
    final shops =
        await service.searchShops(32.8013096, 130.7443793, radiusMeters: 3000);
    expect(shops, hasLength(2));
  });

  test('施設名が違う検索候補を県名一致だけで採用しない', () async {
    final service = BentoService(
        client: MockClient((_) async => http.Response(
            '[{"display_name":"別の高校, 神奈川県","lat":"35.46","lon":"139.52"}]', 200,
            headers: {'content-type': 'application/json; charset=utf-8'})));
    addTearDown(service.dispose);
    expect(await service.geocode('架空中学校 神奈川県'), isEmpty);
  });

  test('会場名の再検索は空白を正規化して再利用する', () async {
    var requests = 0;
    final service = BentoService(
      client: MockClient((_) async {
        requests++;
        return http.Response(
          '[{"display_name":"Tokyo","lat":"35","lon":"139"}]',
          200,
        );
      }),
    );
    addTearDown(service.dispose);
    await service.geocode('Tokyo');
    await service.geocode(' Tokyo　');
    expect(requests, 1);
  });
}
