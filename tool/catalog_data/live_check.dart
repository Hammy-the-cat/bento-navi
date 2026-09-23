// Opt-in live verification; intentionally outside the offline test/ suite.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bento_navi/services/catalog_store.dart';
import 'package:bento_navi/services/bento_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  SharedPreferences.setMockInitialValues({});
  test(
      'published catalog decodes and replaces bundled data through the app service',
      () async {
    final store = CatalogStore();
    final service = BentoService(catalogStore: store);
    addTearDown(service.dispose);
    final timer = Stopwatch()..start();
    await service.warmUp();
    await store.refresh();
    expect(store.version, matches(RegExp(r'^[a-f0-9]{64}$')));
    final shops = await service.loadCatalog();
    expect(shops.length, greaterThanOrEqualTo(10000));
    expect(shops.map((s) => s.id).toSet().length, shops.length);
    final nearby =
        await service.searchCuratedShops(31.4631, 131.2285, radiusMeters: 3000);
    expect(nearby, isNotEmpty);
    final report = {
      'checkedAt': DateTime.now().toUtc().toIso8601String(),
      'version': store.version,
      'count': shops.length,
      'mapped': shops.where((s) => s.hasLocation).length,
      'downloadDecodeAndSearchMs': timer.elapsedMilliseconds,
      'nearbyCurated': nearby.length,
      'platform': 'Windows Flutter test, real HTTP; not an iPhone measurement'
    };
    final file = File('../tmp/bento-catalog-sync/app-live-check.json');
    await file.parent.create(recursive: true);
    await file
        .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    // ignore: avoid_print
    print(jsonEncode(report));
  });
}
