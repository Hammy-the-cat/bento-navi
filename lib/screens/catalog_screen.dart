import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/catalog_shop.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key, required this.loadCatalog, this.changes});
  final Future<List<CatalogShop>> Function() loadCatalog;
  final Listenable? changes;

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  late Future<List<CatalogShop>> _loading;
  String? _prefecture;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loading = widget.loadCatalog();
    widget.changes?.addListener(_reload);
  }

  void _reload() {
    if (mounted) setState(() => _loading = widget.loadCatalog());
  }

  @override
  void dispose() {
    widget.changes?.removeListener(_reload);
    super.dispose();
  }

  Future<void> _open(Uri uri) async {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // Keep the listing usable when a device has no handler for this link.
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('リンクを開けませんでした。店舗情報をご確認ください。')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('地域別の掲載店')),
        backgroundColor: const Color(0xFFFFF8F2),
        body: FutureBuilder<List<CatalogShop>>(
          future: _loading,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: TextButton(
                  onPressed: () => setState(() {
                    _loading = widget.loadCatalog();
                  }),
                  child: const Text('店舗一覧を読み込めませんでした。再試行'),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final all = snapshot.data!;
            final prefectures = all.map((s) => s.prefecture).toSet().toList()
              ..sort();
            final shops = all
                .where(
                  (s) =>
                      (_prefecture == null || s.prefecture == _prefecture) &&
                      s.matches(_query),
                )
                .toList();
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('調査した掲載店を地域や店名で探せます。営業日・予約方法は店舗の案内をご確認ください。'),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _prefecture ?? '',
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: '都道府県',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('すべての掲載地域'),
                          ),
                          ...prefectures.map(
                            (p) => DropdownMenuItem(value: p, child: Text(p)),
                          ),
                        ],
                        onChanged: (p) =>
                            setState(() => _prefecture = p == '' ? null : p),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        decoration: const InputDecoration(
                          labelText: '店名・市町村・住所',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (q) => setState(() => _query = q),
                      ),
                      const SizedBox(height: 8),
                      Text('${shops.length}件 ／ 掲載 ${prefectures.length}都道府県'),
                    ],
                  ),
                ),
                Expanded(
                  child: shops.isEmpty
                      ? const Center(child: Text('該当する掲載店はありません。'))
                      : ListView.builder(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                          itemCount: shops.length,
                          itemBuilder: (context, index) =>
                              _shopCard(shops[index]),
                        ),
                ),
              ],
            );
          },
        ),
      );

  Widget _shopCard(CatalogShop shop) {
    final source = Uri.tryParse(shop.sourceUrl);
    final canOpenSource = source != null &&
        ['https', 'http'].contains(source.scheme) &&
        source.host.isNotEmpty;
    return Card(
      child: ExpansionTile(
        key: PageStorageKey(shop.id),
        title: Text(shop.name),
        subtitle: Text(
          '${shop.prefecture} ${shop.municipality}'
          '${shop.hasLocation ? '' : '\n${shop.coordinateAccuracy.contains('販売店舗なし') ? '配達などの案内・販売店舗なし' : '所在地は店舗へご確認ください'}'}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (shop.address.isNotEmpty) Text(shop.address),
          if (shop.phone.isNotEmpty) Text('電話：${shop.phone}'),
          if (shop.hours.isNotEmpty) Text('営業時間：${shop.hours}'),
          if (shop.closedDays.isNotEmpty) Text('定休日：${shop.closedDays}'),
          if (shop.notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(shop.notes),
            ),
          if (shop.lastVerified.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '情報確認日：${shop.lastVerified}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Wrap(
            spacing: 8,
            children: [
              if (shop.phone.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _open(
                    Uri(
                      scheme: 'tel',
                      path: shop.phone.replaceAll(RegExp(r'[^0-9+]'), ''),
                    ),
                  ),
                  icon: const Icon(Icons.phone_outlined),
                  label: const Text('電話'),
                ),
              if (canOpenSource)
                TextButton.icon(
                  onPressed: () => _open(source),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('店舗の案内'),
                ),
              if (shop.hasLocation)
                TextButton.icon(
                  onPressed: () => _open(
                    Uri.https('www.google.com', '/maps/search/', {
                      'api': '1',
                      'query': '${shop.lat},${shop.lon}',
                    }),
                  ),
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('地図'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
