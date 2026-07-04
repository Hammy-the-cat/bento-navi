import 'package:flutter/material.dart';

/// Web以外のプラットフォーム用スタブ。実広告は表示しない。
Widget buildAdsenseView(String client, String slot, double height) {
  return const SizedBox.shrink();
}
