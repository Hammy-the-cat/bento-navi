/// A source-listed shop may have no public storefront/location.
class CatalogShop {
  CatalogShop.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      name = json['name'] as String,
      prefecture = json['prefecture'] as String? ?? '',
      municipality = json['municipality'] as String? ?? '',
      address = json['address'] as String? ?? '',
      phone = json['phone'] as String? ?? '',
      hours = json['hours'] as String? ?? '',
      closedDays = json['closedDays'] as String? ?? '',
      notes = json['notes'] as String? ?? '',
      sourceUrl = json['sourceUrl'] as String? ?? '',
      lastVerified = json['lastVerified'] as String? ?? '',
      coordinateAccuracy = json['coordinateAccuracy'] as String? ?? '',
      lat = (json['lat'] as num?)?.toDouble(),
      lon = (json['lon'] as num?)?.toDouble();

  final String id,
      name,
      prefecture,
      municipality,
      address,
      phone,
      hours,
      closedDays,
      notes,
      sourceUrl,
      lastVerified,
      coordinateAccuracy;
  final double? lat, lon;
  bool get hasLocation => lat != null && lon != null;
  bool matches(String query) {
    final tokens = query.toLowerCase().trim().split(RegExp(r'[\s　]+'));
    final target = '$name $prefecture $municipality $address'.toLowerCase();
    return tokens.every(target.contains);
  }
}
