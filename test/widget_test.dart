import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bento_navi/main.dart';

void main() {
  testWidgets('ホーム画面が表示される', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const BentoNaviApp());
    await tester.pumpAndSettle();
    expect(find.text('べんとうナビ'), findsOneWidget);
    expect(find.text('会場周辺を検索'), findsOneWidget);
  });

  testWidgets('検索履歴がチップとして表示される', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'search_history': ['西都市 運動公園', '串間中学校'],
    });
    await tester.pumpWidget(const BentoNaviApp());
    await tester.pumpAndSettle();
    expect(find.text('最近の検索'), findsOneWidget);
    expect(find.text('西都市 運動公園'), findsOneWidget);
    expect(find.text('串間中学校'), findsOneWidget);
  });
}
