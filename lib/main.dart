import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  // Flutterのルーターが起動時にURLを書き換えるため、
  // クエリパラメータ(?q=会場名&r=3000&lat=..&lon=..&name=..)はここで先に読んでおく
  String? initialQuery;
  int? initialRadius;
  double? initialLat;
  double? initialLon;
  String? initialName;
  try {
    final params = Uri.base.queryParameters;
    initialQuery = params['q'];
    initialRadius = int.tryParse(params['r'] ?? '');
    initialLat = double.tryParse(params['lat'] ?? '');
    initialLon = double.tryParse(params['lon'] ?? '');
    initialName = params['name'];
  } catch (_) {
    // Uri.baseが取れない環境では無視
  }
  runApp(BentoNaviApp(
    initialQuery: initialQuery,
    initialRadius: initialRadius,
    initialLat: initialLat,
    initialLon: initialLon,
    initialName: initialName,
  ));
}

class BentoNaviApp extends StatelessWidget {
  final String? initialQuery;
  final int? initialRadius;
  final double? initialLat;
  final double? initialLon;
  final String? initialName;

  const BentoNaviApp({
    super.key,
    this.initialQuery,
    this.initialRadius,
    this.initialLat,
    this.initialLon,
    this.initialName,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'べんとうナビ',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFFE65100), // 弁当のオレンジ
      ),
      home: HomeScreen(
        initialQuery: initialQuery,
        initialRadius: initialRadius,
        initialLat: initialLat,
        initialLon: initialLon,
        initialName: initialName,
      ),
    );
  }
}
