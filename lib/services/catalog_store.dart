import 'dart:async';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const catalogOrigin =
    'https://bento-navi-overpass-proxy.excitedcherry0909.workers.dev';
const _cacheKey = 'curated_catalog_v1';

List<Map<String, dynamic>> _decodeAsset(String text) =>
    (jsonDecode(text) as List).cast<Map<String, dynamic>>();

void validateCatalogManifest(Map<String, dynamic> m) {
  final hash = RegExp(r'^[a-f0-9]{64}$');
  if (m['schema'] != 1 ||
      m['source'] != 'curated-sheets' ||
      !hash.hasMatch(m['version'] as String? ?? '') ||
      !hash.hasMatch(m['sha256'] as String? ?? '') ||
      m['path'] != '/catalog/${m['version']}.json.gz' ||
      m['count'] is! int ||
      m['count'] < 10000 ||
      m['count'] > 100000 ||
      m['bytes'] is! int ||
      m['bytes'] < 1 ||
      m['bytes'] > 3000000 ||
      m['jsonBytes'] is! int ||
      m['jsonBytes'] < 1 ||
      m['jsonBytes'] > 20000000) {
    throw const FormatException('Invalid catalog manifest');
  }
}

List<Map<String, dynamic>> decodeCatalog(Map<String, dynamic> input) {
  final m = input['manifest'] as Map<String, dynamic>;
  validateCatalogManifest(m);
  final bytes = input['bytes'] as Uint8List;
  if (bytes.length != m['bytes'] ||
      sha256.convert(bytes).toString() != m['sha256']) {
    throw const FormatException('Catalog checksum mismatch');
  }
  final raw = GZipDecoder().decodeBytes(bytes);
  if (raw.length != m['jsonBytes'] ||
      sha256.convert(raw).toString() != m['version']) {
    throw const FormatException('Catalog content mismatch');
  }
  final shops = _decodeAsset(utf8.decode(raw));
  if (shops.length != m['count']) {
    throw const FormatException('Catalog count mismatch');
  }
  final ids = <String>{};
  for (final s in shops) {
    if (s['id'] is! String ||
        (s['id'] as String).isEmpty ||
        !ids.add(s['id']) ||
        s['name'] is! String ||
        (s['name'] as String).isEmpty ||
        s['prefecture'] is! String ||
        s['municipality'] is! String ||
        ['閉店', '閉店予定'].contains(s['status'])) {
      throw const FormatException('Invalid shop identity or status');
    }
    for (final key in [
      'category',
      'address',
      'phone',
      'hours',
      'closedDays',
      'notes',
      'sourceUrl',
      'status',
      'lastVerified',
      'coordinateAccuracy'
    ]) {
      if (s[key] is! String) throw const FormatException('Invalid shop field');
    }
    final lat = s['lat'], lon = s['lon'];
    if ((lat != null || lon != null) &&
        (lat is! num ||
            lon is! num ||
            !lat.isFinite ||
            !lon.isFinite ||
            lat < 20 ||
            lat > 46 ||
            lon < 122 ||
            lon > 154)) {
      throw const FormatException('Invalid shop coordinates');
    }
  }
  return shops;
}

/// Local-first catalog: a slow/failed refresh never delays a store search.
class CatalogStore extends ChangeNotifier {
  CatalogStore(
      {http.Client? client,
      Future<String> Function()? loadAsset,
      Future<SharedPreferences> Function()? preferences,
      DateTime Function()? clock})
      : _client = client ?? http.Client(),
        _loadAsset =
            loadAsset ?? (() => rootBundle.loadString('assets/shops.json')),
        _preferences = preferences ?? SharedPreferences.getInstance,
        _clock = clock ?? DateTime.now;

  final http.Client _client;
  final Future<String> Function() _loadAsset;
  final Future<SharedPreferences> Function() _preferences;
  final DateTime Function() _clock;
  List<Map<String, dynamic>>? _data;
  Future<List<Map<String, dynamic>>>? _loading;
  Future<void>? _refreshing;
  DateTime? _nextCheck;
  String? version;
  bool _disposed = false;

  Future<List<Map<String, dynamic>>> load() async {
    if (_data != null) return _data!;
    return _loading ??= _readLocal();
  }

  Future<List<Map<String, dynamic>>> _readLocal() async {
    try {
      try {
        final prefs = await _preferences().timeout(const Duration(seconds: 1));
        final text = prefs.getString(_cacheKey);
        if (text != null && text.length <= 4100000) {
          final saved = jsonDecode(text) as Map<String, dynamic>;
          final m = saved['manifest'] as Map<String, dynamic>;
          final shops = await compute(decodeCatalog,
              {'manifest': m, 'bytes': base64Decode(saved['data'] as String)});
          version = m['version'] as String;
          return _data = shops;
        }
      } catch (_) {
        // Storage unavailable/corrupt: the bundled catalog remains usable.
      }
      final shops = await compute(_decodeAsset, await _loadAsset());
      _data = shops;
      return shops;
    } finally {
      _loading = null;
    }
  }

  Future<void> refresh() {
    if (_disposed) return Future.value();
    if (_refreshing != null) return _refreshing!;
    if (_nextCheck != null && _clock().isBefore(_nextCheck!)) {
      return Future.value();
    }
    return _refreshing = _update().whenComplete(() => _refreshing = null);
  }

  Future<void> _update() async {
    _nextCheck = _clock().add(const Duration(minutes: 5));
    try {
      await load();
      final response = await _client
          .get(Uri.parse('$catalogOrigin/catalog/manifest.json'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200 || response.bodyBytes.length > 16384) {
        return;
      }
      final m =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      validateCatalogManifest(m);
      if (version == m['version']) {
        _nextCheck = _clock().add(const Duration(hours: 6));
        return;
      }
      final dataResponse = await _client
          .get(Uri.parse('$catalogOrigin${m['path']}'))
          .timeout(const Duration(seconds: 25));
      if (dataResponse.statusCode != 200) return;
      final shops = await compute(
          decodeCatalog, {'manifest': m, 'bytes': dataResponse.bodyBytes});
      if (_disposed) return;
      try {
        final prefs = await _preferences().timeout(const Duration(seconds: 1));
        await prefs.setString(
            _cacheKey,
            jsonEncode(
                {'manifest': m, 'data': base64Encode(dataResponse.bodyBytes)}));
      } catch (_) {
        // A full storage quota must not prevent this session from updating.
      }
      if (_disposed) return;
      _data = shops;
      version = m['version'] as String;
      _nextCheck = _clock().add(const Duration(hours: 6));
      notifyListeners();
    } catch (_) {
      // Keep the last completely verified catalog on all network/data failures.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _client.close();
    super.dispose();
  }
}
