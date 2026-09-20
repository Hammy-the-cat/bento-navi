import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb, compute;
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart' show rootBundle;

import '../models/shop.dart';
import '../models/catalog_shop.dart';

List<Map<String, dynamic>> _decodeShops(String text) =>
    (jsonDecode(text) as List<dynamic>).cast<Map<String, dynamic>>();

/// Nominatimの利用規約では、アプリを識別できるUser-Agentが必須。
/// ライブラリ既定のUser-Agent(Dart/x.y (dart:io))は403で拒否されるため、
/// iOS/Androidのネイティブビルドでは必ずこれを送る。
/// ※Webではブラウザが自動で付与し、User-Agentの上書きも禁止されているため送らない。
const _userAgent =
    'BentoNavi/1.0 (https://hammy-the-cat.github.io/bento-navi/; excitedcherry0909@gmail.com)';

Map<String, String> get _apiHeaders =>
    kIsWeb ? const {} : const {'User-Agent': _userAgent};

/// OpenStreetMap (Nominatim + Overpass) を使った検索サービス。
/// APIキー不要で利用できる。
class BentoService {
  BentoService({
    http.Client? client,
    this.proxyTimeout = const Duration(seconds: 8),
    this.fallbackTimeout = const Duration(seconds: 4),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration proxyTimeout, fallbackTimeout;
  final _requests = <Completer<void>>{};
  void cancelPendingSearch() {
    _requestGeneration++;
    for (final request in _requests.toList()) {
      if (!request.isCompleted) request.complete();
    }
  }

  void dispose() {
    cancelPendingSearch();
    _client.close();
  }

  Future<http.Response> _request(Uri uri, Duration timeout,
      {String? query}) async {
    final abort = Completer<void>();
    _requests.add(abort);
    final request = http.AbortableRequest(query == null ? 'GET' : 'POST', uri,
        abortTrigger: abort.future)
      ..headers.addAll(_apiHeaders);
    if (query != null) request.bodyFields = {'data': query};
    try {
      return await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout);
    } finally {
      if (!abort.isCompleted) abort.complete();
      _requests.remove(abort);
    }
  }

  Future<void> warmUp() async {
    await _loadCuratedData();
  }

  final _shopCache = <String, List<Shop>>{};
  final _shopCacheTimes = <String, DateTime>{};
  final _placeCache = <String, List<Place>>{};
  Future<List<dynamic>>? _venueLoading;
  Future<void> _geocodeQueue = Future.value();
  DateTime? _lastGeocodeRequest;
  int _requestGeneration = 0;

  Future<List<Place>> _knownVenues(String query) async {
    final venues = await (_venueLoading ??= rootBundle
        .loadString('assets/venues.json')
        .then((value) => jsonDecode(value) as List<dynamic>));
    final compact = query.replaceAll(RegExp(r'[\s　]'), '');
    return venues
        .where((v) => (v['aliases'] as List).any((alias) {
              if (!compact.contains(alias as String)) return false;
              final remaining = compact.replaceFirst(alias, '');
              return (v['region'] as String).contains(remaining);
            }))
        .map((v) => Place(
            displayName: '${v['name']}（${v['address']}）',
            lat: (v['lat'] as num).toDouble(),
            lon: (v['lon'] as num).toDouble()))
        .toList();
  }

  Future<List<Map<String, dynamic>>>? _curatedLoading;
  static const _nominatimBase = 'https://nominatim.openstreetmap.org/search';

  /// Overpassの前段に置いたCloudflare Workersのキャッシュプロキシ。
  /// v1.0で計測した検索の遅さ(3.7〜29秒)への対策として v1.1 で追加。
  /// 詳細: workers/overpass-proxy/。
  /// ここが失敗した場合は下の _overpassEndpoints への直接アクセスに
  /// フォールバックするため、Workerの障害がアプリ全体を止めることはない。
  static const _overpassProxy =
      'https://bento-navi-overpass-proxy.excitedcherry0909.workers.dev/';

  /// Overpassは混雑時に504を返したり無応答になったりするため、
  /// 複数のミラーをタイムアウト付きで順に試す
  /// Overpassのミラー。
  ///
  /// 【重要】ミラーを追加・変更するときは、必ず**日本の実データが返るか**を
  /// 件数で確認すること。HTTPステータスと応答速度だけで判断してはいけない。
  /// 例: overpass.osm.ch はスイス限定のデータしか持たず、日本の座標では
  ///     「200 OK かつ 0件」を高速に返すため、速い優良ミラーに見えてしまう。
  ///
  /// 2026-08-08 実測(東京駅周辺1km・要素数):
  ///   overpass-api.de 100件/5.8秒 / kumi.systems 100件/8.1秒 /
  ///   maps.mail.ru 100件/10.0秒 / osm.ch 0件(日本のデータなし・不採用)
  static const _overpassEndpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
    'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
  ];

  List<Map<String, dynamic>>? _curatedCache;

  /// 施設名の分割に使うキーワード（長いものを先に）
  static const _facilityKeywords = [
    '総合運動公園',
    '運動公園',
    '陸上競技場',
    '総合体育館',
    '体育館',
    '武道館',
    'スタジアム',
    'アリーナ',
    '野球場',
    '球技場',
    '競技場',
    '球場',
    'グラウンド',
    'テニスコート',
    'プール',
    '高等学校',
    '中学校',
    '小学校',
    '高校',
    '大学',
    '公園',
  ];

  /// 会場名・住所から候補地点を検索する。
  /// Nominatimは「県名+施設名」の連結クエリに弱いため、
  /// 見つからない場合はクエリを段階的に変形して再検索する。
  Future<List<Place>> geocode(String query) async {
    final generation = _requestGeneration;
    final normalized =
        query.replaceAll('　', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return [];
    final known = await _knownVenues(normalized);
    if (generation != _requestGeneration) throw StateError('検索が切り替わりました');
    if (known.isNotEmpty) return known;
    final cached = _placeCache[normalized];
    if (cached != null) return List<Place>.of(cached);

    final tokens = normalized.split(' ');
    final attempts = <String>[normalized];

    // 都道府県トークンを外した施設名のみ
    final nonPref =
        tokens.where((t) => !RegExp(r'^.{2,3}[都道府県]$').hasMatch(t)).join(' ');
    if (nonPref.isNotEmpty && nonPref != normalized) {
      attempts.add(nonPref);
    }

    // 施設キーワードの手前で分割（例: 西都市総合運動公園 → 西都市 総合運動公園）
    final base = (nonPref.isEmpty ? normalized : nonPref).replaceAll(' ', '');
    for (final kw in _facilityKeywords) {
      final i = base.indexOf(kw);
      if (i > 0) {
        var prefix = base.substring(0, i);
        attempts.add('$prefix $kw');
        // 「総合」「市民」などの修飾語を落とした形も試す
        final stripped = prefix.replaceAll(
          RegExp(r'(総合|市民|町民|村民|県立|市立|町立|村立)$'),
          '',
        );
        if (stripped.isNotEmpty && stripped != prefix) {
          attempts.add('$stripped $kw');
        }
        if (kw.startsWith('総合')) {
          attempts.add('$prefix ${kw.substring(2)}');
        }
        break;
      }
    }

    final seen = <String>{};
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    Object? lastError;
    List<Place>? fallback;
    for (final attempt in attempts) {
      if (!seen.add(attempt)) continue;
      if (seen.length > 3 || generation != _requestGeneration) break;
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        lastError = TimeoutException('場所検索');
        break;
      }
      List<Place> places;
      try {
        places = await _geocodeOnce(attempt, deadline, generation);
      } catch (error) {
        lastError = error;
        continue;
      }
      // 都道府県だけの一致で、別の学校・施設を採用しない。
      final facilityTokens =
          tokens.where((t) => _facilityKeywords.any(t.contains)).toList();
      places = places
          .where((p) => facilityTokens.every((t) => p.displayName
              .replaceAll(' ', '')
              .contains(t.replaceAll(' ', ''))))
          .toList();
      if (places.isEmpty) {
        fallback ??= [];
        continue;
      }
      // 元のクエリ語（県名・市名など）を含む候補を優先する
      final ranked = _rankByTokens(places, tokens);
      if (_score(ranked.first, tokens) > 0 || attempt == normalized) {
        if (_placeCache.length >= 30) {
          _placeCache.remove(_placeCache.keys.first);
        }
        _placeCache[normalized] = List<Place>.of(ranked);
        return ranked;
      }
      fallback = (fallback == null || fallback.isEmpty) ? ranked : fallback;
    }
    if ((fallback == null || fallback.isEmpty) && lastError != null) {
      throw Exception('場所の検索に通信できませんでした。現在地から検索するか、少し待って再試行してください。');
    }
    return fallback ?? [];
  }

  Future<List<Place>> _geocodeOnce(
      String query, DateTime deadline, int generation) async {
    final previous = _geocodeQueue;
    final done = Completer<void>();
    _geocodeQueue = done.future;
    try {
      await previous;
      final last = _lastGeocodeRequest;
      if (last != null) {
        final delay = const Duration(milliseconds: 1100) -
            DateTime.now().difference(last);
        if (delay > Duration.zero) await Future<void>.delayed(delay);
      }
      if (generation != _requestGeneration ||
          !DateTime.now().isBefore(deadline)) {
        throw TimeoutException('場所検索');
      }
      _lastGeocodeRequest = DateTime.now();
      final remaining = deadline.difference(DateTime.now());
      return await _geocodeRequest(
          query,
          remaining < const Duration(seconds: 4)
              ? remaining
              : const Duration(seconds: 4));
    } finally {
      done.complete();
    }
  }

  Future<List<Place>> _geocodeRequest(String query, Duration timeout) async {
    final uri = Uri.parse(_nominatimBase).replace(
      queryParameters: {
        'q': query,
        'format': 'json',
        'limit': '5',
        'countrycodes': 'jp',
        'accept-language': 'ja',
      },
    );
    final res = await _request(uri, timeout);
    if (res.statusCode != 200) {
      throw Exception('場所の検索に失敗しました (HTTP ${res.statusCode})');
    }
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return list
        .map(
          (e) => Place(
            displayName: e['display_name'] as String? ?? '不明な場所',
            lat: double.parse(e['lat'] as String),
            lon: double.parse(e['lon'] as String),
          ),
        )
        .toList();
  }

  int _score(Place p, List<String> tokens) {
    var score = 0;
    for (final t in tokens) {
      if (t.isNotEmpty && p.displayName.contains(t)) score++;
      // 「宮崎県」→「宮崎」のように接尾辞を外した形でも照合
      final stripped = t.replaceAll(RegExp(r'[都道府県市区町村]$'), '');
      if (stripped.length >= 2 && p.displayName.contains(stripped)) score++;
    }
    return score;
  }

  List<Place> _rankByTokens(List<Place> places, List<String> tokens) {
    final ranked = List<Place>.from(places);
    ranked.sort((a, b) => _score(b, tokens).compareTo(_score(a, tokens)));
    return ranked;
  }

  /// HTTP 200でもOverpassのremarkは失敗・不完全な応答。
  List<dynamic> _elements(http.Response response) {
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic> ||
        decoded['elements'] is! List ||
        decoded['remark'] != null) {
      throw const FormatException('店舗情報の取得が完了していません');
    }
    return decoded['elements'] as List<dynamic>;
  }

  /// 固定店舗を先に表示。外部検索は最大8秒+予備4秒で完了させる。
  Future<List<Shop>> searchShops(
    double lat,
    double lon, {
    int radiusMeters = 1000,
    void Function(List<Shop>)? onInitialResults,
    void Function(String)? onNotice,
  }) async {
    final generation = _requestGeneration;
    final key = '$lat,$lon,$radiusMeters';
    final cached = _shopCache[key];
    if (cached != null &&
        DateTime.now().difference(_shopCacheTimes[key]!) <
            const Duration(minutes: 5)) {
      return List<Shop>.of(cached);
    }
    // 同じ中心の広い検索が完了済みなら、半径を狭める操作は通信不要。
    // 完全な応答のみがキャッシュされるため、部分結果を0件と誤認しない。
    for (final entry in _shopCache.entries) {
      final parts = entry.key.split(',');
      if (parts[0] == '$lat' &&
          parts[1] == '$lon' &&
          int.parse(parts[2]) >= radiusMeters &&
          DateTime.now().difference(_shopCacheTimes[entry.key]!) <
              const Duration(minutes: 5)) {
        return entry.value
            .where((shop) => shop.distanceMeters <= radiusMeters)
            .toList();
      }
    }
    final curated =
        await searchCuratedShops(lat, lon, radiusMeters: radiusMeters);
    if (generation != _requestGeneration) throw StateError('検索が切り替わりました');
    if (curated.isNotEmpty) onInitialResults?.call(List<Shop>.of(curated));
    List<dynamic>? elements;
    try {
      final uri = Uri.parse(_overpassProxy).replace(queryParameters: {
        'lat': '$lat',
        'lon': '$lon',
        'radius': '$radiusMeters',
      });
      elements = _elements(await _request(
          uri,
          curated.isEmpty
              ? proxyTimeout
              : Duration(milliseconds: proxyTimeout.inMilliseconds ~/ 2)));
    } catch (_) {
      // プロキシ障害の予備経路は1回だけ。長いミラー巡回を重ねない。
    }
    if (generation != _requestGeneration) throw StateError('検索が切り替わりました');
    if (elements == null) {
      final around = 'around:$radiusMeters,$lat,$lon';
      final query = '''
[out:json][timeout:4];
(
  nwr["shop"~"^(convenience|supermarket|deli|bakery)\$"]($around);
  nwr["amenity"="fast_food"]($around);
  nwr["amenity"="restaurant"]["takeaway"~"^(yes|only)\$"]($around);
);
out center tags;
''';
      try {
        elements = _elements(await _request(
            Uri.parse(_overpassEndpoints.first),
            curated.isEmpty
                ? fallbackTimeout
                : Duration(milliseconds: fallbackTimeout.inMilliseconds ~/ 2),
            query: query));
      } catch (_) {
        if (curated.isNotEmpty) {
          onNotice?.call('登録済み店舗を表示しています。通信できなかったため、ほかの周辺店舗は確認できていません。');
          return curated;
        }
        throw Exception(
            '通信できず、周辺の店舗を確認できませんでした。店舗が0件という意味ではありません。再検索するか、地域別の掲載店をご利用ください。');
      }
    }
    final shops = <Shop>[];
    for (final e in elements) {
      if (e is! Map<String, dynamic>) continue;
      final tags = e['tags'] is Map<String, dynamic>
          ? e['tags'] as Map<String, dynamic>
          : <String, dynamic>{};
      final name = tags['name'] ?? tags['brand'];
      if (name is! String || name.trim().isEmpty) continue;

      double? sLat;
      double? sLon;
      if (e['lat'] is num && e['lon'] is num) {
        sLat = (e['lat'] as num).toDouble();
        sLon = (e['lon'] as num).toDouble();
      } else if (e['center'] is Map &&
          e['center']['lat'] is num &&
          e['center']['lon'] is num) {
        sLat = (e['center']['lat'] as num).toDouble();
        sLon = (e['center']['lon'] as num).toDouble();
      }
      if (sLat == null ||
          sLon == null ||
          !sLat.isFinite ||
          !sLon.isFinite ||
          haversineMeters(lat, lon, sLat, sLon) > radiusMeters) {
        continue;
      }

      shops.add(
        Shop(
          name: name,
          category: _categorize(tags),
          lat: sLat,
          lon: sLon,
          distanceMeters: haversineMeters(lat, lon, sLat, sLon),
          openingHours: tags['opening_hours'] as String?,
          brand: tags['brand'] as String?,
        ),
      );
    }

    // 同名でも別地点のチェーン店舗は残す。
    shops.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    final merged = <Shop>[...curated];
    for (final shop in shops) {
      final duplicate = merged.any((other) =>
          _normalizeName(other.name) == _normalizeName(shop.name) &&
          haversineMeters(other.lat, other.lon, shop.lat, shop.lon) < 60);
      if (!duplicate) merged.add(shop);
    }
    merged.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    if (_shopCache.length >= 30) {
      final oldest = _shopCache.keys.first;
      _shopCache.remove(oldest);
      _shopCacheTimes.remove(oldest);
    }
    _shopCache[key] = List<Shop>.of(merged);
    _shopCacheTimes[key] = DateTime.now();
    return merged;
  }

  /// スプレッドシートで確認した店舗を、APIに依存せず検索する。
  Future<List<Shop>> searchCuratedShops(
    double lat,
    double lon, {
    int radiusMeters = 1000,
  }) async {
    final data = await _loadCuratedData();
    final shops = <Shop>[];
    for (final item in data) {
      // Addressless delivery/mobile shops remain available in the catalog.
      if (item['lat'] is! num || item['lon'] is! num) continue;
      final shopLat = (item['lat'] as num).toDouble();
      final shopLon = (item['lon'] as num).toDouble();
      final distance = haversineMeters(lat, lon, shopLat, shopLon);
      if (distance > radiusMeters) continue;

      shops.add(
        Shop(
          name: item['name'] as String,
          category: _curatedCategory(item['category'] as String? ?? ''),
          lat: shopLat,
          lon: shopLon,
          distanceMeters: distance,
          openingHours: _nonEmpty(item['hours']),
          address: _nonEmpty(item['address']),
          phone: _nonEmpty(item['phone']),
          notes: _nonEmpty(item['notes']),
          sourceUrl: _nonEmpty(item['sourceUrl']),
          verificationStatus: _nonEmpty(item['status']),
          isCurated: true,
        ),
      );
    }
    shops.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return shops;
  }

  Future<List<CatalogShop>> loadCatalog() async =>
      (await _loadCuratedData()).map(CatalogShop.fromJson).toList();

  Future<List<Map<String, dynamic>>> _loadCuratedData() async {
    if (_curatedCache != null) return _curatedCache!;
    return _curatedLoading ??= _readCuratedData();
  }

  Future<List<Map<String, dynamic>>> _readCuratedData() async {
    try {
      final text = await rootBundle.loadString('assets/shops.json');
      final data = await compute(_decodeShops, text);
      _curatedCache = data;
      return data;
    } finally {
      _curatedLoading = null;
    }
  }

  String? _nonEmpty(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  String _normalizeName(String name) =>
      name.toLowerCase().replaceAll(RegExp(r'[\s　・･（）()]'), '');

  ShopCategory _curatedCategory(String value) {
    if (value.contains('スーパー')) return ShopCategory.supermarket;
    if (RegExp(r'弁当|惣菜|仕出し|おにぎり|持ち帰り寿司').hasMatch(value)) {
      return ShopCategory.bentoDeli;
    }
    if (RegExp(r'パン|サンドイッチ').hasMatch(value)) {
      return ShopCategory.bakery;
    }
    if (RegExp(r'唐揚げ|揚げ物|ファストフード').hasMatch(value)) {
      return ShopCategory.fastFood;
    }
    if (RegExp(r'カフェ|食堂|レストラン|居酒屋|焼肉|中華|うなぎ|寿司|テイクアウト').hasMatch(value)) {
      return ShopCategory.restaurant;
    }
    return ShopCategory.other;
  }

  static final _bentoNamePattern = RegExp(
    r'弁当|べんとう|ほか弁|ほっともっと|かまどや|オリジン|惣菜|仕出し',
  );

  ShopCategory _categorize(Map<String, dynamic> tags) {
    // 店名・ブランド・cuisineから弁当屋を最優先で判定
    // (ほっともっと等のチェーンはOSM上fast_food扱いだが、利用者にとっては弁当屋)
    final name = '${tags['name'] ?? ''} ${tags['brand'] ?? ''}';
    final cuisine = tags['cuisine'] as String? ?? '';
    if (_bentoNamePattern.hasMatch(name) || cuisine.contains('bento')) {
      return ShopCategory.bentoDeli;
    }
    switch (tags['shop'] as String?) {
      case 'convenience':
        return ShopCategory.convenience;
      case 'supermarket':
        return ShopCategory.supermarket;
      case 'deli':
        return ShopCategory.bentoDeli;
      case 'bakery':
        return ShopCategory.bakery;
    }
    if (tags['amenity'] == 'fast_food') {
      return ShopCategory.fastFood;
    }
    if (tags['amenity'] == 'restaurant') {
      return ShopCategory.restaurant;
    }
    return ShopCategory.other;
  }
}
