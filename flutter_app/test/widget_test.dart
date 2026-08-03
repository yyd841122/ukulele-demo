// 测试:默认显示第一首歌;顶栏下拉框能切到第二首。
// 这一步不连手机也能跑(flutter test),是"代码真能跑 + 切歌真能切"的快速证据。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ukulele_demo/main.dart';

void main() {
  testWidgets('默认显示 Over the Rainbow', (tester) async {
    await tester.pumpWidget(const UkuleleApp());

    expect(find.textContaining('Somewhere Over the Rainbow'), findsOneWidget);
    expect(find.text('Am'), findsWidgets);
    expect(find.textContaining('way up high'), findsOneWidget);
  });

  testWidgets('下拉框能切换到 What a Wonderful World', (tester) async {
    await tester.pumpWidget(const UkuleleApp());

    // 点顶栏的歌名下拉框,打开列表
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();

    // 选中第二首
    await tester.tap(find.textContaining('What a Wonderful World'));
    await tester.pumpAndSettle();

    // 现在应该看到第二首的歌词,且看不到第一首的歌词了
    expect(find.textContaining('what a wonderful world'), findsOneWidget);
    expect(find.textContaining('way up high'), findsNothing);
  });
}
