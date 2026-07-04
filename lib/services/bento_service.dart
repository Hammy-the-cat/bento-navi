import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

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
    final normalized = query
        .replaceAll('　', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return [];

    final tokens = normalized.split(' ');
    final attempts = <String>[normalized];

    // 都道府県トークンを外した施設名のみ
    final nonPref = tokens
        .where((t) => !RegExp(r'^.{2,3}[都道府県]$').hasMatch(t))
        .join(' ');
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
            RegExp(r'(総合|市民|町民|村民|県立|市立|町立|村立)$'), '');
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
    final uri = Uri.parse(_nominatimBase).replace(queryParameters: {
      'q': query,
      'format': 'json',
      'limit': '5',
      'countrycodes': 'jp',
      'accept-language': 'ja',
    });
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('場所の検索に失敗しました (HTTP ${res.statusCode})');
    }
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return list
        .map((e) => Place(
              displayName: e['display_name'] as String? ?? '不明な場所',
              lat: double.parse(e['lat'] as String),
              lon: double.parse(e['lon'] as String),
            ))
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
    final query = '''
[out:json][timeout:25];
(
  nwr["shop"~"^(convenience|supermarket|deli|bakery)\$"](around:$radiusMeters,$lat,$lon);
  nwr["amenity"="fast_food"](around:$radiusMeters,$lat,$lon);
);
out center tags 80;
''';
    http.Response? res;
    Object? lastError;
    for (final endpoint in _overpassEndpoints) {
      try {
        final r = await http.post(
          Uri.parse(endpoint),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {'data': query},
        ).timeout(const Duration(seconds: 20));
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

      shops.add(Shop(
        name: name,
        category: _categorize(tags),
        lat: sLat,
        lon: sLon,
        distanceMeters: haversineMeters(lat, lon, sLat, sLon),
        openingHours: tags['opening_hours'] as String?,
        brand: tags['brand'] as String?,
      ));
    }

    // 重複（同名・近接）を除去し距離順に並べる
    shops.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    final seen = <String>{};
    final unique = <Shop>[];
    for (final s in shops) {
      final key = '${s.name}_${(s.distanceMeters / 50).round()}';
      if (seen.add(key)) unique.add(s);
    }
    return unique;
  }

  ShopCategory _categorize(Map<String, dynamic> tags) {
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
    return ShopCategory.other;
  }
}
