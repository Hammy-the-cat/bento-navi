import '../models/shop.dart';

String normalizeSchoolText(String value) =>
    String.fromCharCodes(value.runes.map(
      (c) => c >= 0xff01 && c <= 0xff5e ? c - 0xfee0 : c,
    )).replaceAll(RegExp(r'[\s　]'), '').replaceAll('ヶ', 'ケ');

String schoolNameKey(String value) => normalizeSchoolText(value)
    .replaceAll('高等学校', '高校')
    .replaceAll('中学校', '中')
    .replaceAll('小学校', '小');

String _core(String value) =>
    value.replaceFirst(RegExp(r'^.*?[都道府県市区町村]立'), '');

bool isSchoolQuery(String query) => RegExp(
      r'(中学校|小学校|高等学校|高校|大学|義務教育学校|中等教育学校|支援学校|高専|幼稚園)|\S+[中小高](?:[\s　]|$)',
    ).hasMatch(query);

/// Prevent the external provider's fuzzy match from choosing another school.
bool matchesSchoolQuery(String query, String displayName) {
  final names = query
      .replaceAll('　', ' ')
      .split(RegExp(r'\s+'))
      .where(isSchoolQuery)
      .toList();
  final candidate = schoolNameKey(displayName);
  if (names.isNotEmpty) {
    for (final token in query.replaceAll('　', ' ').split(RegExp(r'\s+'))) {
      if (RegExp(r'^(北海道|東京都|京都府|大阪府|.{2,3}県)').hasMatch(token) &&
          !normalizeSchoolText(displayName)
              .contains(normalizeSchoolText(token))) {
        return false;
      }
    }
  }
  return names.every((name) => candidate.contains(schoolNameKey(name)));
}

class _School {
  _School(this.row)
      : address = normalizeSchoolText(row['address'] as String),
        names = <String>{
          for (final name in [row['name'], ...(row['aliases'] as List)]) ...[
            schoolNameKey(name as String),
            _core(schoolNameKey(name))
          ],
        };
  final Map<String, dynamic> row;
  final String address;
  final Set<String> names;
  Place place({bool suggestion = false}) => Place(
        displayName:
            '${row['name']}${(row['campus'] as String).isEmpty ? '' : ' ${row['campus']}'}（${row['address']}）',
        lat: (row['lat'] as num).toDouble(),
        lon: (row['lon'] as num).toDouble(),
        requiresConfirmation: suggestion,
      );
}

/// Offline matching keeps geographic constraints even when a name is corrected.
class SchoolSearch {
  SchoolSearch(List<Map<String, dynamic>> rows) {
    for (final row in rows) {
      (_byPrefecture[row['prefecture'] as String] ??= []).add(_School(row));
    }
  }
  final _byPrefecture = <String, List<_School>>{};

  List<Place> search(String query) {
    if (!isSchoolQuery(query)) return [];
    final text = schoolNameKey(query);
    String? pref;
    for (final candidate in _byPrefecture.keys) {
      if (text.contains(candidate)) {
        pref = candidate;
        break;
      }
      final short = candidate.replaceFirst(RegExp(r'[都府県]$'), '');
      if (query.replaceAll('　', ' ').split(RegExp(r'\s+')).contains(short)) {
        pref = candidate;
        break;
      }
    }
    final candidates = pref == null
        ? _byPrefecture.values.expand((value) => value)
        : _byPrefecture[pref]!;
    final exact = <Place>[];
    for (final school in candidates) {
      if (school.names.any((name) =>
          name.length >= 2 &&
          text.contains(name) &&
          school.address.contains(text.replaceFirst(name, '')))) {
        exact.add(school.place());
      }
    }
    if (exact.isNotEmpty) return exact;

    // Typo suggestions require a supplied prefecture. Never cross prefectures
    // merely because a similar school name is common elsewhere in Japan.
    if (pref == null) return [];
    var tokens = query.replaceAll('　', ' ').split(RegExp(r'\s+'));
    final nameTokens = tokens.where(isSchoolQuery).toList();
    if (nameTokens.length != 1) return [];
    final name = _core(schoolNameKey(nameTokens.single.replaceAll(pref, '')));
    final region =
        schoolNameKey(tokens.where((t) => t != nameTokens.single).join())
            .replaceAll(pref, '')
            .replaceAll(pref.replaceFirst(RegExp(r'[都府県]$'), ''), '');
    if (name.length < 3 || name.length > 30) {
      return [];
    }
    final suggestions = <Place>[];
    for (final school in candidates) {
      if (!school.address.contains(region)) continue;
      if (school.names.any((candidate) => _oneEdit(name, candidate))) {
        suggestions.add(school.place(suggestion: true));
      }
    }
    return suggestions;
  }
}

bool _oneEdit(String a, String b) {
  // Preserve the school level (e.g. don't suggest a primary school for a junior high).
  if (a.isEmpty ||
      b.isEmpty ||
      a[a.length - 1] != b[b.length - 1] ||
      (a.length - b.length).abs() > 1) {
    return false;
  }
  var i = 0, j = 0, edits = 0;
  while (i < a.length && j < b.length) {
    if (a[i] == b[j]) {
      i++;
      j++;
      continue;
    }
    if (++edits > 1) return false;
    if (a.length >= b.length) i++;
    if (b.length >= a.length) j++;
  }
  return edits + (a.length - i) + (b.length - j) == 1;
}
