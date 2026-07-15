import 'package:flutter_test/flutter_test.dart';

import 'package:bento_navi/models/shop.dart';

Shop shopWithNotes(String? notes) => Shop(
      name: 'テスト店舗',
      category: ShopCategory.bentoDeli,
      lat: 31.9,
      lon: 131.4,
      distanceMeters: 100,
      notes: notes,
    );

void main() {
  test('明確な配達対応は配達可になる', () {
    expect(
      shopWithNotes('指定場所への配達に対応').deliveryAvailability,
      DeliveryAvailability.available,
    );
  });

  test('個数や地域などの条件がある場合は条件付配達になる', () {
    expect(
      shopWithNotes('5個以上・2km圏内は配達可').deliveryAvailability,
      DeliveryAvailability.conditional,
    );
  });

  test('曜日によって配達しない場合は条件付配達になる', () {
    expect(
      shopWithNotes('平日は戸別配達対応、土日祝は個別配達なし').deliveryAvailability,
      DeliveryAvailability.conditional,
    );
  });

  test('配達なしと明記された場合は配達なしになる', () {
    expect(
      shopWithNotes('店舗受取のみ。配達なし').deliveryAvailability,
      DeliveryAvailability.unavailable,
    );
  });

  test('確認が必要な記載や情報がない場合は配達要確認になる', () {
    expect(
      shopWithNotes('宅配等は公式ページで確認').deliveryAvailability,
      DeliveryAvailability.unknown,
    );
    expect(
      shopWithNotes(null).deliveryAvailability,
      DeliveryAvailability.unknown,
    );
  });
}
