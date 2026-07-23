import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/ad_config.dart';
import '../models/shop.dart';
import '../services/bento_service.dart';
import '../widgets/ad_banner.dart';

/// カテゴリごとのテーマカラー
Color categoryColor(ShopCategory c) {
  switch (c) {
    case ShopCategory.convenience:
      return const Color(0xFF1E88E5);
    case ShopCategory.supermarket:
      return const Color(0xFF43A047);
    case ShopCategory.bentoDeli:
      return const Color(0xFFE53935);
    case ShopCategory.bakery:
      return const Color(0xFF8D6E63);
    case ShopCategory.fastFood:
      return const Color(0xFFFB8C00);
    case ShopCategory.restaurant:
      return const Color(0xFF00897B);
    case ShopCategory.other:
      return const Color(0xFF757575);
  }
}

Color deliveryColor(DeliveryAvailability availability) {
  switch (availability) {
    case DeliveryAvailability.available:
      return const Color(0xFF2E7D32);
    case DeliveryAvailability.conditional:
      return const Color(0xFFEF6C00);
    case DeliveryAvailability.unavailable:
      return const Color(0xFFC62828);
    case DeliveryAvailability.unknown:
      return const Color(0xFF616161);
  }
}

class HomeScreen extends StatefulWidget {
  final String? initialQuery;
  final int? initialRadius;
  final double? initialLat;
  final double? initialLon;
  final String? initialName;

  const HomeScreen({
    super.key,
    this.initialQuery,
    this.initialRadius,
    this.initialLat,
    this.initialLon,
    this.initialName,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _service = BentoService();
  final _queryController = TextEditingController();

  bool _loading = false;
  String? _error;
  Place? _selectedPlace;
  List<Shop> _shops = [];
  bool _searched = false;
  bool _showMap = false;
  int _radius = 1000;
  final Set<ShopCategory> _activeFilters = {};
  List<String> _history = [];

  static const _radiusOptions = [500, 1000, 2000, 3000];
  static const _historyKey = 'search_history';

  @override
  void initState() {
    super.initState();
    _loadHistory();
    // Web版: ?q=会場名&r=3000 で開くと自動検索する
    final r = widget.initialRadius;
    if (r != null && _radiusOptions.contains(r)) {
      _radius = r;
    }
    final q = widget.initialQuery;
    if (q != null && q.trim().isNotEmpty) {
      _queryController.text = q;
    }
    final lat = widget.initialLat;
    final lon = widget.initialLon;
    if (lat != null && lon != null) {
      // 共有リンクに座標が入っていれば、ジオコーディングを介さず正確な地点で検索
      final place = Place(
        displayName: widget.initialName ?? q ?? '共有された場所',
        lat: lat,
        lon: lon,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) => _searchAround(place));
    } else if (q != null && q.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _searchByQuery(autoPick: true),
      );
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final list = sp.getStringList(_historyKey) ?? [];
      if (mounted) setState(() => _history = list);
    } catch (e) {
      // 保存領域が使えない環境では履歴なしで動かす
      debugPrint('history load failed: $e');
    }
  }

  Future<void> _addHistory(String query) async {
    try {
      final list = List<String>.from(_history)
        ..remove(query)
        ..insert(0, query);
      final trimmed = list.take(6).toList();
      setState(() => _history = trimmed);
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList(_historyKey, trimmed);
    } catch (e) {
      debugPrint('history save failed: $e');
    }
  }

  Future<void> _copyShareLink() async {
    final query = _queryController.text.trim();
    final place = _selectedPlace;
    if (query.isEmpty && place == null) return;
    // 座標を埋め込むことで、開いた側でジオコーディングの揺れが起きないようにする
    var params = 'q=${Uri.encodeComponent(query)}&r=$_radius';
    if (place != null) {
      params +=
          '&lat=${place.lat.toStringAsFixed(6)}'
          '&lon=${place.lon.toStringAsFixed(6)}'
          '&name=${Uri.encodeComponent(place.displayName)}';
    }
    String link;
    try {
      // GitHub Pagesのようなサブパス配信でも壊れないよう、現在のパスを使う
      link = '${Uri.base.origin}${Uri.base.path}?$params';
    } catch (_) {
      link = 'https://bento-navi.example/?$params';
    }
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('共有リンクをコピーしました。チームに送ろう！'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _searchByQuery({bool autoPick = false}) async {
    final query = _queryController.text.trim();
    if (query.isEmpty) {
      setState(() => _error = '会場名や住所を入力してください（例: 県総合運動公園 宮崎）');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final places = await _service.geocode(query);
      if (places.isEmpty) {
        setState(() {
          _loading = false;
          _error = '場所が見つかりませんでした。市区町村名も付けて試してください。';
        });
        return;
      }
      Place? place = places.first;
      if (!autoPick && places.length > 1 && mounted) {
        place = await _pickPlace(places);
        if (place == null) {
          setState(() => _loading = false);
          return;
        }
      }
      await _addHistory(query);
      await _searchAround(place);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = '検索中にエラーが発生しました: $e';
      });
    }
  }

  Future<void> _searchByCurrentLocation() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() {
          _loading = false;
          _error =
              '位置情報がブロックされています。ブラウザのアドレスバーの鍵アイコン→「位置情報」から許可するか、'
              '上の入力欄に会場名を入れて検索してください。';
        });
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 12),
        ),
      );
      await _searchAround(
        Place(displayName: '現在地', lat: pos.latitude, lon: pos.longitude),
      );
    } on TimeoutException {
      setState(() {
        _loading = false;
        _error = '現在地の取得がタイムアウトしました。電波状況の良い場所で再試行するか、会場名で検索してください。';
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = '現在地を取得できませんでした。ブラウザで位置情報が許可されているか確認するか、会場名で検索してください。';
      });
    }
  }

  Future<Place?> _pickPlace(List<Place> places) {
    return showModalBottomSheet<Place>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'どの場所ですか？',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
            ...places.map(
              (p) => ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFFFF3E0),
                  child: Icon(Icons.place_outlined, color: Color(0xFFE65100)),
                ),
                title: Text(
                  p.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.pop(context, p),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _searchAround(Place place) async {
    setState(() {
      _loading = true;
      _error = null;
      _selectedPlace = place;
    });
    try {
      final shops = await _service.searchShops(
        place.lat,
        place.lon,
        radiusMeters: _radius,
      );
      setState(() {
        _loading = false;
        _shops = shops;
        _searched = true;
        _activeFilters.clear();
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = '店舗の検索に失敗しました: $e';
      });
    }
  }

  Future<void> _openMap(Shop shop) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${shop.lat},${shop.lon}&travelmode=walking',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _callShop(Shop shop) async {
    final phone = shop.phone;
    if (phone == null) return;

    final dialNumber = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    var launched = false;
    try {
      launched = await launchUrl(
        Uri(scheme: 'tel', path: dialNumber),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      launched = false;
    }

    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('電話アプリを開けませんでした。電話番号: $phone')),
      );
    }
  }

  void _resetSearch() {
    FocusManager.instance.primaryFocus?.unfocus();
    _queryController.clear();
    setState(() {
      _loading = false;
      _error = null;
      _selectedPlace = null;
      _shops = [];
      _searched = false;
      _showMap = false;
      _radius = 1000;
      _activeFilters.clear();
    });
  }

  List<Shop> get _visibleShops {
    if (_activeFilters.isEmpty) return _shops;
    return _shops.where((s) => _activeFilters.contains(s.category)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F2),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _buildHero(theme),
          Transform.translate(
            offset: const Offset(0, -44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  _buildSearchCard(theme),
                  const SizedBox(height: 14),
                  if (_error != null) _buildError(theme),
                  if (_loading) _buildLoading(theme),
                  if (!_loading && _searched) ..._buildResults(theme),
                  if (!_loading && !_searched && _history.isNotEmpty)
                    _buildHistory(theme),
                  if (!_loading && !_searched) _buildTipsCard(theme),
                  _buildFooterLinks(theme),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── ヒーローヘッダー ──────────────────────────────
  Widget _buildHero(ThemeData theme) {
    return Container(
      height: 210,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF7043), Color(0xFFE65100), Color(0xFFBF360C)],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Stack(
        children: [
          // 背景の飾り円
          Positioned(
            top: -40,
            right: -30,
            child: _decoCircle(140, Colors.white.withValues(alpha: 0.08)),
          ),
          Positioned(
            bottom: 20,
            left: -20,
            child: _decoCircle(90, Colors.white.withValues(alpha: 0.06)),
          ),
          Positioned(
            top: 30,
            right: 40,
            child: Text(
              '🍱',
              style: TextStyle(
                fontSize: 64,
                color: Colors.white.withValues(alpha: 0.9),
                shadows: const [Shadow(color: Colors.black26, blurRadius: 12)],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '遠征のお供に',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'べんとうナビ',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                      shadows: [Shadow(color: Colors.black26, blurRadius: 8)],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '知らない土地でも、試合前の腹ごしらえはおまかせ。',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _decoCircle(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }

  // ── 検索カード ──────────────────────────────
  Widget _buildSearchCard(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFBF360C).withValues(alpha: 0.14),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.stadium_outlined,
                  color: Color(0xFFE65100),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '試合会場の近くで探す',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'コンビニ・スーパー・弁当屋がすぐ見つかる',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _queryController,
            decoration: InputDecoration(
              hintText: '例: 県総合運動公園 宮崎',
              prefixIcon: const Icon(Icons.search, color: Color(0xFFE65100)),
              filled: true,
              fillColor: const Color(0xFFF7F3EE),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: Color(0xFFE65100),
                  width: 2,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _searchByQuery(),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.radar, size: 18, color: Colors.grey.shade600),
              const SizedBox(width: 6),
              Text(
                '検索範囲',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  children: _radiusOptions.map((r) {
                    final label = r < 1000 ? '${r}m' : '${r ~/ 1000}km';
                    final selected = _radius == r;
                    return ChoiceChip(
                      label: Text(label),
                      selected: selected,
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : Colors.grey.shade700,
                      ),
                      selectedColor: const Color(0xFFE65100),
                      backgroundColor: const Color(0xFFF7F3EE),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide.none,
                      ),
                      onSelected: (_) => setState(() => _radius = r),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF7043), Color(0xFFE65100)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFFE65100,
                          ).withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: _loading ? null : _searchByQuery,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: const Icon(Icons.search),
                      label: const Text(
                        '会場周辺を検索',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : _searchByCurrentLocation,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFE65100),
                    side: const BorderSide(
                      color: Color(0xFFE65100),
                      width: 1.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.my_location, size: 18),
                  label: const Text(
                    '現在地',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── ローディング(検索中に広告を表示) ──────────────
  Widget _buildLoading(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: const [
          CircularProgressIndicator(color: Color(0xFFE65100)),
          SizedBox(height: 16),
          Text('お弁当スポットを探しています…', style: TextStyle(color: Color(0xFF8D6E63))),
          SizedBox(height: 20),
          AdBanner(slot: AdConfig.slotLoading, height: 250),
        ],
      ),
    );
  }

  // ── エラー表示 ──────────────────────────────
  Widget _buildError(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFCDD2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFC62828)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(color: Color(0xFFC62828), fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  // ── 検索結果 ──────────────────────────────
  List<Widget> _buildResults(ThemeData theme) {
    final shops = _visibleShops;
    final categories = _shops.map((s) => s.category).toSet().toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final nearest = _shops.isEmpty ? null : _shops.first;

    return [
      // サマリーヘッダー
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.place, color: Color(0xFFE65100), size: 20),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _selectedPlace?.displayName ?? '',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_queryController.text.trim().isNotEmpty)
                  IconButton(
                    onPressed: _copyShareLink,
                    icon: const Icon(
                      Icons.share_outlined,
                      size: 20,
                      color: Color(0xFFE65100),
                    ),
                    tooltip: 'チームに共有リンクをコピー',
                    visualDensity: VisualDensity.compact,
                  ),
                TextButton.icon(
                  onPressed: _resetSearch,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('リセット'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFE65100),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _statBadge('${_shops.length}', '件ヒット', const Color(0xFFE65100)),
                const SizedBox(width: 10),
                if (nearest != null)
                  _statBadge(
                    nearest.distanceLabel,
                    '最寄り',
                    const Color(0xFF43A047),
                  ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),

      // リスト / 地図 切り替え
      if (_shops.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              _segButton(
                'リスト',
                Icons.format_list_bulleted,
                !_showMap,
                () => setState(() => _showMap = false),
              ),
              _segButton(
                '地図',
                Icons.map_outlined,
                _showMap,
                () => setState(() => _showMap = true),
              ),
            ],
          ),
        ),

      // カテゴリフィルタ
      if (categories.length > 1)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: categories.map((c) {
                final selected = _activeFilters.contains(c);
                final color = categoryColor(c);
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text('${c.emoji} ${c.label}'),
                    selected: selected,
                    checkmarkColor: Colors.white,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : color,
                    ),
                    selectedColor: color,
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(color: color.withValues(alpha: 0.4)),
                    ),
                    onSelected: (sel) => setState(() {
                      sel ? _activeFilters.add(c) : _activeFilters.remove(c);
                    }),
                  ),
                );
              }).toList(),
            ),
          ),
        ),

      // 空の場合
      if (_shops.isEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              const Text('😢', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 8),
              Text(
                'この範囲では見つかりませんでした',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '検索範囲を広げてみてください',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),

      if (_showMap && _shops.isNotEmpty)
        _buildMapView(shops)
      else
        ..._buildShopListWithAds(shops),
    ];
  }

  /// 店舗リストに一定間隔で広告を挟む
  List<Widget> _buildShopListWithAds(List<Shop> shops) {
    final widgets = <Widget>[];
    for (var i = 0; i < shops.length; i++) {
      widgets.add(
        _ShopCard(
          shop: shops[i],
          onOpenMap: () => _openMap(shops[i]),
          onCall: () => _callShop(shops[i]),
        ),
      );
      final isInterval = (i + 1) % AdConfig.inFeedInterval == 0;
      if (isInterval && i != shops.length - 1) {
        widgets.add(const AdBanner(slot: AdConfig.slotInFeed, height: 90));
      }
    }
    return widgets;
  }

  Widget _segButton(
    String label,
    IconData icon,
    bool selected,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(
                    colors: [Color(0xFFFF7043), Color(0xFFE65100)],
                  )
                : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: selected ? Colors.white : Colors.grey.shade600,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: selected ? Colors.white : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _zoomForRadius(int radius) {
    switch (radius) {
      case 500:
        return 15.6;
      case 1000:
        return 14.8;
      case 2000:
        return 13.9;
      default:
        return 13.4;
    }
  }

  Widget _buildMapView(List<Shop> shops) {
    final place = _selectedPlace;
    if (place == null) return const SizedBox.shrink();
    final center = LatLng(place.lat, place.lon);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          height: 420,
          child: FlutterMap(
            options: MapOptions(
              initialCenter: center,
              initialZoom: _zoomForRadius(_radius),
              maxZoom: 18,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'bento_navi',
              ),
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: center,
                    radius: _radius.toDouble(),
                    useRadiusInMeter: true,
                    color: const Color(0xFFE65100).withValues(alpha: 0.06),
                    borderColor: const Color(
                      0xFFE65100,
                    ).withValues(alpha: 0.45),
                    borderStrokeWidth: 1.5,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  // 会場マーカー
                  Marker(
                    point: center,
                    width: 46,
                    height: 46,
                    child: const Icon(
                      Icons.place,
                      color: Color(0xFFD32F2F),
                      size: 46,
                    ),
                  ),
                  // 店舗マーカー
                  ...shops.map(
                    (s) => Marker(
                      point: LatLng(s.lat, s.lon),
                      width: 38,
                      height: 38,
                      child: GestureDetector(
                        onTap: () => _showShopSheet(s),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: categoryColor(s.category),
                              width: 2.5,
                            ),
                            boxShadow: const [
                              BoxShadow(color: Colors.black26, blurRadius: 6),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              s.category.emoji,
                              style: const TextStyle(fontSize: 17),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SimpleAttributionWidget(
                source: Text('OpenStreetMap contributors'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showShopSheet(Shop shop) {
    final color = categoryColor(shop.category);
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Text(
                        shop.category.emoji,
                        style: const TextStyle(fontSize: 26),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shop.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${shop.category.label} ・ ${shop.distanceLabel} ・ ${shop.walkLabel}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (shop.isCurated) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    shop.verificationStatus == '要営業確認'
                        ? '調査データ・営業内容は要確認'
                        : '調査済み店舗データ',
                    style: const TextStyle(
                      color: Color(0xFF2E7D32),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
              if (shop.address != null) ...[
                const SizedBox(height: 10),
                _shopDetailRow(Icons.location_on_outlined, shop.address!),
              ],
              if (shop.phone != null) ...[
                const SizedBox(height: 8),
                _shopDetailRow(Icons.phone_outlined, shop.phone!),
              ],
              const SizedBox(height: 8),
              _DeliveryBadge(availability: shop.deliveryAvailability),
              if (shop.openingHours != null) ...[
                const SizedBox(height: 10),
                _shopDetailRow(Icons.schedule, '営業時間: ${shop.openingHours}'),
              ],
              if (shop.notes != null) ...[
                const SizedBox(height: 8),
                _shopDetailRow(Icons.info_outline, shop.notes!),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  if (shop.phone != null) ...[
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: () => _callShop(shop),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF2E7D32),
                            side: const BorderSide(color: Color(0xFF2E7D32)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.phone),
                          label: const Text(
                            '電話する',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _openMap(shop);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE65100),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.directions_walk),
                        label: const Text(
                          '経路を見る',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                  if (shop.sourceUrl != null) ...[
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: () => launchUrl(Uri.parse(shop.sourceUrl!)),
                      tooltip: '情報源を開く',
                      icon: const Icon(Icons.open_in_new),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shopDetailRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: Colors.grey.shade500),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ),
      ],
    );
  }

  Widget _statBadge(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color.withValues(alpha: 0.8),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ── フッターリンク ──────────────────────────
  Future<void> _openPage(String page) async {
    try {
      await launchUrl(Uri.base.resolve(page), mode: LaunchMode.platformDefault);
    } catch (_) {
      // Web以外や解決失敗時は何もしない
    }
  }

  Widget _buildFooterLinks(ThemeData theme) {
    final linkStyle = TextStyle(
      fontSize: 12,
      color: Colors.grey.shade600,
      decoration: TextDecoration.underline,
      decorationColor: Colors.grey.shade400,
    );
    Widget link(String label, String page) => InkWell(
      onTap: () => _openPage(page),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(label, style: linkStyle),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              link('使い方', 'guide.html'),
              link('遠征弁当のコツ集', 'tips.html'),
              link('プライバシーポリシー', 'privacy.html'),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '地図データ © OpenStreetMap contributors',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  // ── 検索履歴 ──────────────────────────────
  Widget _buildHistory(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Row(
              children: [
                Icon(Icons.history, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Text(
                  '最近の検索',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _history.map((q) {
              return ActionChip(
                avatar: const Icon(
                  Icons.replay,
                  size: 14,
                  color: Color(0xFFE65100),
                ),
                label: Text(
                  q,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: Colors.orange.shade200),
                ),
                onPressed: () {
                  _queryController.text = q;
                  _searchByQuery();
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── Tips カード ──────────────────────────────
  Widget _buildTipsCard(ThemeData theme) {
    const tips = [
      ['🕖', '試合当日の朝は会場近くのコンビニが売り切れがち。少し離れた店も候補に。'],
      ['🍙', 'スーパーの弁当・惣菜コーナーは朝9〜10時頃から並び始めることが多い。'],
      ['🥶', '夏場は保冷バッグ持参が安心。傷みにくいおにぎり系がおすすめ。'],
      ['🚌', 'チームでまとめ買いするなら、前日にスーパーへ予約の電話をしておくと確実。'],
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('💡', style: TextStyle(fontSize: 18)),
              ),
              const SizedBox(width: 10),
              Text(
                '遠征弁当のコツ',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...tips.asMap().entries.map((entry) {
            final t = entry.value;
            final isLast = entry.key == tips.length - 1;
            return Container(
              margin: EdgeInsets.only(bottom: isLast ? 0 : 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFAF6F1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t[0], style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      t[1],
                      style: theme.textTheme.bodySmall?.copyWith(
                        height: 1.5,
                        color: const Color(0xFF5D4037),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _DeliveryBadge extends StatelessWidget {
  final DeliveryAvailability availability;

  const _DeliveryBadge({required this.availability});

  @override
  Widget build(BuildContext context) {
    final color = deliveryColor(availability);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_shipping_outlined, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            availability.label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 店舗カード ──────────────────────────────
class _ShopCard extends StatelessWidget {
  final Shop shop;
  final VoidCallback onOpenMap;
  final VoidCallback onCall;

  const _ShopCard({
    required this.shop,
    required this.onOpenMap,
    required this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = categoryColor(shop.category);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onOpenMap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // カテゴリアイコン
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(
                      shop.category.emoji,
                      style: const TextStyle(fontSize: 26),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                // 店舗情報
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shop.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              shop.category.label,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: color,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.directions_walk,
                            size: 13,
                            color: Colors.grey.shade500,
                          ),
                          Text(
                            shop.walkLabel.replaceAll('徒歩 ', ''),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                      if (shop.openingHours != null) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(
                              Icons.schedule,
                              size: 12,
                              color: Colors.grey.shade500,
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                shop.openingHours!,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.shade600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 4),
                      _DeliveryBadge(
                        availability: shop.deliveryAvailability,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // 距離バッジ + 経路
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      shop.distanceLabel,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (shop.phone != null) ...[
                      SizedBox(
                        height: 30,
                        child: OutlinedButton.icon(
                          onPressed: onCall,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF2E7D32),
                            side: const BorderSide(color: Color(0xFF81C784)),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(0, 30),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(Icons.phone, size: 13),
                          label: const Text(
                            '電話',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF7043), Color(0xFFE65100)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.near_me, size: 12, color: Colors.white),
                          SizedBox(width: 3),
                          Text(
                            '経路',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
