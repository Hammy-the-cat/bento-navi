import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter/services.dart' show rootBundle;

import '../models/shop.dart';

/// OpenStreetMap (Nominatim + Overpass) を使った検索サービス。
/// APIキー不要で利用できる。
class BentoService {
  static const _nominatimBase = 'https://nominatim.openstreetmap.org/search';

  /// Overpassは混雑時に504を返したり無応答になったりするため、
  /// 複数のミラーをタイムアウト付きで順に試す
  static const _overpassEndpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
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
    final normalized =
        query.replaceAll('　', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return [];

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
    List<Place>? fallback;
    for (final attempt in attempts) {
      if (!seen.add(attempt)) continue;
      if (fallback != null) {
        // Nominatimの利用規約（1リクエスト/秒）に合わせて間隔を空ける
        await Future.delayed(const Duration(milliseconds: 1100));
      }
      final places = await _geocodeOnce(attempt);
      if (places.isEmpty) {
        fallback ??= [];
        continue;
      }
      // 元のクエリ語（県名・市名など）を含む候補を優先する
      final ranked = _rankByTokens(places, tokens);
      if (_score(ranked.first, tokens) > 0 || attempt == normalized) {
        return ranked;
      }
      fallback = (fallback == null || fallback.isEmpty) ? ranked : fallback;
    }
    return fallback ?? [];
  }

  Future<List<Place>> _geocodeOnce(String query) async {
    final uri = Uri.parse(_nominatimBase).replace(
      queryParameters: {
        'q': query,
        'format': 'json',
        'limit': '5',
        'countrycodes': 'jp',
        'accept-language': 'ja',
      },
    );
    final res = await http.get(uri);
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

  /// 指定地点の周辺で弁当が買える店を検索する
  Future<List<Shop>> searchShops(
    double lat,
    double lon, {
    int radiusMeters = 1000,
  }) async {
    final curated = await searchCuratedShops(
      lat,
      lon,
      radiusMeters: radiusMeters,
    );
    // 地元の弁当屋はOSM上でジャンルタグがなく店名だけのことが多いため、
    // タグ検索に加えて店名の正規表現でも拾う
    final query = '''
[out:json][timeout:25];
(
  nwr["shop"~"^(convenience|supermarket|deli|bakery)\$"](around:$radiusMeters,$lat,$lon);
  nwr["amenity"="fast_food"](around:$radiusMeters,$lat,$lon);
  nwr["name"~"弁当|べんとう|ほか弁|ほっともっと|かまどや|オリジン|惣菜|仕出し"](around:$radiusMeters,$lat,$lon);
  nwr["amenity"="restaurant"]["takeaway"~"^(yes|only)\$"](around:$radiusMeters,$lat,$lon);
);
out center tags 100;
''';
    http.Response? res;
    Object? lastError;
    // 調査済み店舗がある地域では、OSMは補完用途として最初の1系統だけを
    // 短時間試す。応答がなくても固定データをすぐ返せるようにする。
    final endpoints =
        curated.isEmpty ? _overpassEndpoints : _overpassEndpoints.take(1);
    final timeout = Duration(seconds: curated.isEmpty ? 20 : 5);
    for (final endpoint in endpoints) {
      try {
        final r = await http.post(
          Uri.parse(endpoint),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {'data': query},
        ).timeout(timeout);
        if (r.statusCode == 200) {
          res = r;
          break;
        }
        lastError = Exception('HTTP ${r.statusCode}');
      } catch (e) {
        lastError = e;
      }
    }
    if (res == null) {
      if (curated.isNotEmpty) return curated;
      throw Exception('周辺の店舗検索に失敗しました ($lastError)。少し待って再試行してください。');
    }
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final elements = (json['elements'] as List<dynamic>?) ?? [];

    final shops = <Shop>[];
    for (final e in elements) {
      final tags = (e['tags'] as Map<String, dynamic>?) ?? {};
      final name = tags['name'] as String? ?? tags['brand'] as String?;
      if (name == null) continue; // 名無しの店は除外

      double? sLat;
      double? sLon;
      if (e['lat'] != null) {
        sLat = (e['lat'] as num).toDouble();
        sLon = (e['lon'] as num).toDouble();
      } else if (e['center'] != null) {
        sLat = (e['center']['lat'] as num).toDouble();
        sLon = (e['center']['lon'] as num).toDouble();
      }
      if (sLat == null || sLon == null) continue;

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

    // 重複（同名・近接）を除去し距離順に並べる
    shops.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    final seen = <String>{};
    final unique = <Shop>[];
    for (final s in shops) {
      final key = '${s.name}_${(s.distanceMeters / 50).round()}';
      if (seen.add(key)) unique.add(s);
    }
    // 調査済みデータを優先し、OSMに同名店舗がある場合は重複を除く。
    final merged = <Shop>[...curated];
    final seenNames = curated.map((s) => _normalizeName(s.name)).toSet();
    for (final shop in unique) {
      if (seenNames.add(_normalizeName(shop.name))) merged.add(shop);
    }
    merged.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
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

  Future<List<Map<String, dynamic>>> _loadCuratedData() async {
    if (_curatedCache != null) return _curatedCache!;
    final text = await rootBundle.loadString('assets/shops.json');
    final list = jsonDecode(text) as List<dynamic>;
    return _curatedCache = list.cast<Map<String, dynamic>>();
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
