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
    final search = service
        .searchShops(
          31.4631,
          131.2285,
          radiusMeters: 10000,
          onInitialResults: (shops) {
            expect(shops, isNotEmpty);
            expect(shops.every((shop) => shop.isCurated), isTrue);
            initial.complete();
          },
        )
        .then((shops) {
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
    await service.searchShops(31.4631, 131.2285, radiusMeters: 500);
    expect(requests, 2);
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
