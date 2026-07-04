// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:js' as js;
// ignore: undefined_prefixed_name
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

final Set<String> _registeredViews = {};

/// AdSenseの<ins>タグをHtmlElementViewとして埋め込む(Web専用)。
Widget buildAdsenseView(String client, String slot, double height) {
  final viewType = 'adsense-$slot';
  if (_registeredViews.add(viewType)) {
    // ignore: undefined_prefixed_name
    ui.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final ins = html.Element.tag('ins')
        ..className = 'adsbygoogle'
        ..style.display = 'block'
        ..style.width = '100%'
        ..style.height = '${height.round()}px'
        ..setAttribute('data-ad-client', client)
        ..setAttribute('data-ad-slot', slot)
        ..setAttribute('data-ad-format', 'auto')
        ..setAttribute('data-full-width-responsive', 'false');
      // 要素がDOMに挿入されてから広告のロードを要求する
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        try {
          final ads = js.context['adsbygoogle'];
          if (ads != null) {
            (ads as js.JsObject).callMethod('push', [js.JsObject.jsify({})]);
          }
        } catch (_) {
          // 広告ブロッカー等で失敗しても本体機能には影響させない
        }
      });
      return ins;
    });
  }
  return HtmlElementView(viewType: viewType);
}
