import 'package:flutter/material.dart';

/// Web・デスクトップ向けのスタブ。
/// AdMob(google_mobile_ads)はモバイル専用のため、ここでは何もしない。

/// モバイル広告SDKの初期化(この環境では不要)
Future<void> initMobileAds() async {}

/// AdMobバナー(この環境では非対応なのでnullを返し、呼び出し側で
/// AdSenseまたはプレースホルダーにフォールバックさせる)
Widget? buildAdmobBanner(double height) => null;
