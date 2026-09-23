import 'dart:async';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bento_navi/services/catalog_store.dart';
import 'package:bento_navi/services/bento_service.dart';

Map<String, dynamic> shop(int i, String name) => {
      'id': 'S$i',
      'name': name,
      'category': '弁当',
      'prefecture': '宮崎県',
      'municipality': '宮崎市',
      'address': '宮崎市$i',
      'lat': 31.9,
      'lon': 131.4,
      'phone': '0985-00-0000',
      'hours': '',
      'closedDays': '',
      'notes': '',
      'sourceUrl': '',
      'status': '確認済み',
      'lastVerified': '2026-09-23',
      'coordinateAccuracy': '店舗地点'
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final seed = jsonEncode([shop(0, '同梱店舗')]);
  final raw =
      utf8.encode(jsonEncode(List.generate(10000, (i) => shop(i, '更新店舗$i'))));
  final packed = GZipEncoder().encode(raw);
  final version = sha256.convert(raw).toString();
  final manifest = {
    'schema': 1,
    'source': 'curated-sheets',
    'count': 10000,
    'version': version,
    'sha256': sha256.convert(packed).toString(),
    'bytes': packed.length,
    'jsonBytes': raw.length,
    'path': '/catalog/$version.json.gz'
  };
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'slow refresh never blocks search; update persists and works offline after restart',
      () async {
    final gate = Completer<void>();
    final started = Completer<void>();
    var calls = 0;
    final store = CatalogStore(
        loadAsset: () async => seed,
        client: MockClient((r) async {
          calls++;
          if (r.url.path.endsWith('manifest.json')) {
            started.complete();
            await gate.future;
            return http.Response(jsonEncode(manifest), 200);
          }
          return http.Response.bytes(packed, 200);
        }));
    final service = BentoService(
        catalogStore: store,
        client: MockClient((r) async => http.Response('{"elements":[]}', 200)));
    addTearDown(service.dispose);
    await service.warmUp();
    await started.future;
    expect((await service.searchShops(31.9, 131.4)).single.name, '同梱店舗');
    gate.complete();
    await store.refresh();
    expect((await service.searchShops(31.9, 131.4)).length, 10000);
    expect((await service.loadCatalog()).first.name, '更新店舗0');
    await store.refresh();
    expect(calls, 2);
    final offline = CatalogStore(
        loadAsset: () async => seed,
        client: MockClient((_) async => throw Exception('offline')));
    addTearDown(offline.dispose);
    expect((await offline.load()).length, 10000);
    await offline.refresh();
    expect(offline.version, version);
    expect((await offline.load()).first['name'], '更新店舗0');
  });

  test(
      'same version only fetches manifest, bad downloads never replace good data',
      () async {
    var now = DateTime(2026, 9, 23);
    var mode = 'valid';
    var downloads = 0;
    final store = CatalogStore(
        loadAsset: () async => seed,
        clock: () => now,
        client: MockClient((r) async {
          if (r.url.path.endsWith('manifest.json')) {
            final m = Map.of(manifest);
            if (mode == 'bad') {
              m['version'] = 'a' * 64;
              m['path'] = '/catalog/${m['version']}.json.gz';
            }
            return http.Response(jsonEncode(m), 200);
          }
          downloads++;
          return http.Response.bytes(mode == 'bad' ? [1, 2, 3] : packed, 200);
        }));
    addTearDown(store.dispose);
    await store.refresh();
    expect(downloads, 1);
    now = now.add(const Duration(hours: 7));
    await store.refresh();
    expect(downloads, 1);
    mode = 'bad';
    now = now.add(const Duration(hours: 7));
    await store.refresh();
    expect(store.version, version);
    expect((await store.load()).length, 10000);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('curated_catalog_v1'), contains(version));
  });

  test('invalid cache and unavailable storage fall back to bundled catalog',
      () async {
    SharedPreferences.setMockInitialValues({'curated_catalog_v1': 'not json'});
    final store = CatalogStore(loadAsset: () async => seed);
    addTearDown(store.dispose);
    expect((await store.load()).single['name'], '同梱店舗');
    final noStorage = CatalogStore(
        loadAsset: () async => seed,
        preferences: () async => throw Exception('storage denied'));
    addTearDown(noStorage.dispose);
    expect((await noStorage.load()).single['name'], '同梱店舗');
  });
}
