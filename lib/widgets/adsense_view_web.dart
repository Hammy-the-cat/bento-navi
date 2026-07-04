import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

final Set<String> _registeredViews = {};

/// AdSenseの<ins>タグをHtmlElementViewとして埋め込む(Web専用)。
Widget buildAdsenseView(String client, String slot, double height) {
  final viewType = 'adsense-$slot';
  if (_registeredViews.add(viewType)) {
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final ins =
          web.document.createElement('ins') as web.HTMLElement;
      ins.className = 'adsbygoogle';
      ins.style.display = 'block';
      ins.style.width = '100%';
      ins.style.height = '${height.round()}px';
      ins.setAttribute('data-ad-client', client);
      ins.setAttribute('data-ad-slot', slot);
      ins.setAttribute('data-ad-format', 'auto');
      ins.setAttribute('data-full-width-responsive', 'false');
      // 要素がDOMに挿入されてから広告のロードを要求する
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        try {
          final ads = globalContext.getProperty('adsbygoogle'.toJS);
          if (ads.isDefinedAndNotNull) {
            (ads as JSObject).callMethod('push'.toJS, JSObject());
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
