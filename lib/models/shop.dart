import 'dart:math' as math;

/// 弁当が買える店のカテゴリ
enum ShopCategory {
  convenience,
  supermarket,
  bentoDeli,
  bakery,
  fastFood,
  restaurant,
  other,
}

enum DeliveryAvailability {
  available,
  conditional,
  unavailable,
  unknown,
}

extension DeliveryAvailabilityInfo on DeliveryAvailability {
  String get label {
    switch (this) {
      case DeliveryAvailability.available:
        return '配達可';
      case DeliveryAvailability.conditional:
        return '条件付配達';
      case DeliveryAvailability.unavailable:
        return '配達なし';
      case DeliveryAvailability.unknown:
        return '配達要確認';
    }
  }
}

extension ShopCategoryInfo on ShopCategory {
  String get label {
    switch (this) {
      case ShopCategory.convenience:
        return 'コンビニ';
      case ShopCategory.supermarket:
        return 'スーパー';
      case ShopCategory.bentoDeli:
        return '弁当・惣菜';
      case ShopCategory.bakery:
        return 'パン屋';
      case ShopCategory.fastFood:
        return 'ファストフード';
      case ShopCategory.restaurant:
        return '食堂(持ち帰り可)';
      case ShopCategory.other:
        return 'その他';
    }
  }

  String get emoji {
    switch (this) {
      case ShopCategory.convenience:
        return '🏪';
      case ShopCategory.supermarket:
        return '🛒';
      case ShopCategory.bentoDeli:
        return '🍱';
      case ShopCategory.bakery:
        return '🥐';
      case ShopCategory.fastFood:
        return '🍔';
      case ShopCategory.restaurant:
        return '🍚';
      case ShopCategory.other:
        return '🏬';
    }
  }
}

/// 検索結果の店舗
class Shop {
  final String name;
  final ShopCategory category;
  final double lat;
  final double lon;
  final double distanceMeters;
  final String? openingHours;
  final String? brand;
  final String? address;
  final String? phone;
  final String? notes;
  final String? sourceUrl;
  final String? verificationStatus;
  final bool isCurated;

  const Shop({
    required this.name,
    required this.category,
    required this.lat,
    required this.lon,
    required this.distanceMeters,
    this.openingHours,
    this.brand,
    this.address,
    this.phone,
    this.notes,
    this.sourceUrl,
    this.verificationStatus,
    this.isCurated = false,
  });

  String get distanceLabel {
    if (distanceMeters < 1000) {
      return '${distanceMeters.round()} m';
    }
    return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
  }

  /// 徒歩の目安時間（分速80m）
  String get walkLabel {
    final minutes = (distanceMeters / 80).ceil();
    return '徒歩 約$minutes分';
  }

  DeliveryAvailability get deliveryAvailability {
    final text = '$name ${notes ?? ''}';
    final hasDeliveryWord = RegExp(r'配達|宅配|配食|デリバリー').hasMatch(text);
    if (!hasDeliveryWord) return DeliveryAvailability.unknown;

    final hasUnavailable = RegExp(
      r'配達なし|配達不可|配達は行っていない|配達していない|店舗受取のみ|店頭受取のみ',
    ).hasMatch(text);
    final hasAvailable = RegExp(
      r'配達可|配達可能|配達対応|配達あり|へ配達|市内配達|町内配達|全域へ配達|'
      r'指定場所への配達|配達中心|配達専業|配達実績|配達・|配達。|配達（|宅配弁当|配食サービス',
    ).hasMatch(text);

    if (hasAvailable) {
      final hasConditions = hasUnavailable ||
          RegExp(
            r'要相談|相談可|条件|範囲|以上|から配達|予約|前日|当日|一部|平日|'
            r'地域|近隣|周辺|限定|のみ配達',
          ).hasMatch(text);
      return hasConditions
          ? DeliveryAvailability.conditional
          : DeliveryAvailability.available;
    }
    if (hasUnavailable) return DeliveryAvailability.unavailable;
    return DeliveryAvailability.unknown;
  }
}

/// ジオコーディング結果
class Place {
  final String displayName;
  final double lat;
  final double lon;

  const Place({
    required this.displayName,
    required this.lat,
    required this.lon,
  });
}

/// 2地点間の距離（メートル、ハバーサイン公式）
double haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  final dLat = _rad(lat2 - lat1);
  final dLon = _rad(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(lat1)) *
          math.cos(_rad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _rad(double deg) => deg * math.pi / 180;
