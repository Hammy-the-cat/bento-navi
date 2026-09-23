// Explicit live check: flutter test tool/shop_data/live_service_check.dart
// Exercises the existing iOS service contract, including curated/OSM merging.
import 'dart:convert';
import 'dart:io';
import 'package:bento_navi/services/bento_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Opt-in probe only: disable flutter_test's deliberately blocked networking.
  HttpOverrides.global = null;
  test('報告された3会場を既存サービスからR2経由で検索できる', () async {
    final service = BentoService();
    addTearDown(service.dispose);
    final results = <Map<String, dynamic>>[];
    for (final query in ['帯山中学校 熊本', 'アイビースタジアム 宮崎', '市場中学校 神奈川']) {
      final clock = Stopwatch()..start();
      final place = (await service.geocode(query)).first;
      String? notice;
      final shops = await service.searchShops(place.lat, place.lon,
          radiusMeters: 3000, onNotice: (value) => notice = value);
      expect(notice, isNull, reason: query);
      expect(shops, isNotEmpty, reason: query);
      expect(shops.every((s) => s.distanceMeters <= 3000), isTrue);
      results.add({
        'query': query,
        'count': shops.length,
        'ms': clock.elapsedMilliseconds
      });
    }
    final output = File('../tmp/bento-r2-migration/native-service-check.json');
    output.parent.createSync(recursive: true);
    output
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(results));
    // ignore: avoid_print
    print(jsonEncode(results));
  }, timeout: const Timeout(Duration(seconds: 60)));
}
