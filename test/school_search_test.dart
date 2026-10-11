import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bento_navi/services/bento_service.dart';
import 'package:bento_navi/services/school_search.dart';
import 'package:bento_navi/services/school_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final packed = File('assets/schools/schools.json.gz').readAsBytesSync();
  final manifest =
      jsonDecode(File('assets/schools/manifest.json').readAsStringSync())
          as Map<String, dynamic>;
  final rows =
      (jsonDecode(utf8.decode(GZipDecoder().decodeBytes(packed)))['schools']
              as List)
          .cast<Map<String, dynamic>>();
  final search = SchoolSearch(rows);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('深浦中・地域の連結・語順・全角空白を正しい学校へ解決する', () {
    for (final query in [
      '深浦中　青森県西津軽郡',
      '青森県西津軽郡 深浦中学校',
      '深浦中学校青森県西津軽郡',
      '深浦中 青森'
    ]) {
      final places = search.search(query);
      expect(places, hasLength(1), reason: query);
      expect(places.single.displayName, contains('深浦町立深浦中学校'));
      expect(places.single.lat, closeTo(40.651451, 0.00001));
      expect(places.single.requiresConfirmation, isFalse);
    }
  });
  test('青峰中は青嶺中の候補を返すが、必ず選択を要求する', () {
    final suggestions = search.search('青峰中 佐賀県');
    expect(suggestions, isNotEmpty);
    expect(suggestions.every((p) => p.requiresConfirmation), isTrue);
    expect(
        suggestions.any((p) => p.displayName.contains('伊万里市立青嶺中学校')), isTrue);
    expect(suggestions.every((p) => p.displayName.contains('佐賀県')), isTrue);
    final exact = search.search('青嶺中 佐賀県');
    expect(exact, hasLength(1));
    expect(exact.single.requiresConfirmation, isFalse);
  });
  test('県指定の違い・別校・地名だけの一致で採用しない', () {
    expect(search.search('深浦中 青森県横浜市'), isEmpty);
    expect(search.search('深浦中 神奈川県横浜市').every((p) => p.requiresConfirmation),
        isTrue);
    expect(matchesSchoolQuery('深浦中 青森県西津軽郡', '深浦町立大戸瀬中学校 青森県'), isFalse);
    expect(matchesSchoolQuery('青峰中 佐賀県', '青峰 宮城県'), isFalse);
  });
  test('全国9地域の任意の中学校をデータから正しく解決する', () {
    for (final pref in [
      '北海道',
      '宮城県',
      '愛知県',
      '神奈川県',
      '石川県',
      '大阪府',
      '広島県',
      '愛媛県',
      '佐賀県'
    ]) {
      final school = rows.firstWhere((s) =>
          s['prefecture'] == pref && (s['name'] as String).endsWith('中学校'));
      final result = search.search('${school['name']} $pref');
      expect(
          result.any((p) => p.lat == school['lat'] && p.lon == school['lon']),
          isTrue,
          reason: '${school['name']} $pref');
      expect(result.every((p) => p.displayName.contains(pref)), isTrue);
    }
  });
  test('全国索引は47都道府県を含み改ざんを検知する', () {
    expect(decodeSchoolData({'manifest': manifest, 'bytes': packed}),
        hasLength(manifest['count']));
    final damaged = packed.sublist(0)..[10] ^= 1;
    expect(() => decodeSchoolData({'manifest': manifest, 'bytes': damaged}),
        throwsFormatException);
    expect(
        () => validateSchoolManifest(
            {...manifest, 'path': 'https://example.com/data'}),
        throwsFormatException);
  });
  test('学校検索は外部検索に一度も接続せず繰り返し使用できる', () async {
    var calls = 0;
    final store = SchoolStore(loadAsset: () async => jsonEncode(rows));
    final service = BentoService(
        schoolStore: store,
        client: MockClient((_) async {
          calls++;
          throw StateError('School searches must work offline');
        }));
    addTearDown(service.dispose);
    for (final query in ['深浦中 青森県西津軽郡', '青峰中 佐賀県', '青嶺中 佐賀県']) {
      expect(await service.geocode(query), isNotEmpty);
    }
    final watch = Stopwatch()..start();
    for (var i = 0; i < 20; i++) {
      await service.geocode('深浦中 青森県西津軽郡');
    }
    watch.stop();
    // A generous regression ceiling, not an iPhone performance claim.
    expect(watch.elapsedMilliseconds, lessThan(2000));
    expect(calls, 0);
  });
  test('初回オフライン・更新保存・再起動・破損キャッシュの復旧', () async {
    final offline =
        SchoolStore(client: MockClient((_) async => http.Response('', 503)));
    expect(await offline.load(), hasLength(manifest['count']));
    await offline.refresh();
    expect(await offline.load(), hasLength(manifest['count']));
    offline.dispose();
    final store = SchoolStore(
        loadAsset: () async => '[]',
        client: MockClient((r) async => r.url.path.endsWith('manifest.json')
            ? http.Response(jsonEncode(manifest), 200)
            : http.Response.bytes(packed, 200)));
    await store.refresh();
    expect(await store.load(), hasLength(manifest['count']));
    store.dispose();
    final reboot = SchoolStore(
        loadAsset: () async => throw StateError('Should use saved data'));
    expect(await reboot.load(), hasLength(manifest['count']));
    reboot.dispose();
    SharedPreferences.setMockInitialValues({'school_index_v1': 'broken'});
    final recovered = SchoolStore();
    expect(await recovered.load(), hasLength(manifest['count']));
    recovered.dispose();
  });
}
