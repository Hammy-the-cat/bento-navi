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

  const Shop({
    required this.name,
    required this.category,
    required this.lat,
    required this.lon,
    required this.distanceMeters,
    this.openingHours,
    this.brand,
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
