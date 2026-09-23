import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bento_navi/services/bento_service.dart';

// Explicit live check only: flutter test tool/regional_live_check.dart
// Not part of the offline test/ suite. Uses the same HTTP service as iOS.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('全国9地域の実通信・検索範囲を記録する', () async {
    HttpOverrides.global = null;
    final results = <Map<String, dynamic>>[];
    const cases = [
      ['北海道', '札幌駅 北海道', '札幌駅'],
      ['東北', '仙台駅 宮城県', '杜の陽だまり'],
      ['中部', '名古屋駅 愛知県', 'タワーズテラス'],
      ['関東', '東京駅 東京都', '東京駅'],
      ['北陸', '金沢駅 石川県', '中階段'],
      ['近畿', '大阪駅 大阪府', '梅田三丁目'],
      ['中国', '広島駅 広島県', '広島駅南北自由通路'],
      ['四国', '高松駅 香川県', '20,'],
      ['九州', '博多駅 福岡県', '中央街７号線'],
    ];
    final service = BentoService();
    addTearDown(service.dispose);
    await service.warmUp();
    for (final c in cases) {
      final filter = Platform.environment['BENTO_REGION'];
      if (filter != null && c[0] != filter) continue;
      final watch = Stopwatch()..start();
      final row = <String, dynamic>{
        'region': c[0],
        'query': c[1],
        'radius': 3000
      };
      try {
        final places = await service.geocode(c[1]);
        row['geocodeMs'] = watch.elapsedMilliseconds;
        final matches =
            places.where((p) => p.displayName.contains(c[2])).toList();
        if (matches.isEmpty) throw StateError('指定した駅候補がない');
        final p = matches.first;
        row.addAll({'place': p.displayName, 'lat': p.lat, 'lon': p.lon});
        final shops = await service.searchShops(p.lat, p.lon,
            radiusMeters: 3000,
            onInitialResults: (shops) {
              row['initialMs'] = watch.elapsedMilliseconds;
              row['initialCount'] = shops.length;
            },
            onNotice: (notice) => row['notice'] = notice);
        row['totalMs'] = watch.elapsedMilliseconds;
        row['count'] = shops.length;
        row['outsideRadius'] =
            shops.where((s) => s.distanceMeters > 3000).length;
        expect(row['outsideRadius'], 0);
        final narrowWatch = Stopwatch()..start();
        try {
          final smaller = await service.searchShops(p.lat, p.lon,
              radiusMeters: 500,
              onNotice: (notice) => row['narrowNotice'] = notice);
          row['narrowCount'] = smaller.length;
          expect(smaller.every((s) => s.distanceMeters <= 500), isTrue);
        } catch (error) {
          row['narrowError'] = '$error';
        }
        row['narrowMs'] = narrowWatch.elapsedMilliseconds;
      } catch (error) {
        row['error'] = '$error';
        row['totalMs'] = watch.elapsedMilliseconds;
      }
      results.add(row);
      stdout.writeln(jsonEncode(row));
      final suffix = Platform.environment['BENTO_REGION'] ?? 'all';
      final file = File('../tmp/bento-regional-check/live-$suffix.json');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(results));
      await Future<void>.delayed(const Duration(milliseconds: 1200));
    }
  }, timeout: const Timeout(Duration(minutes: 6)));
}
