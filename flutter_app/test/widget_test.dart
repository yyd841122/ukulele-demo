// 测试:默认显示第一首歌;顶栏下拉框能切到第二首。
// 这一步不连手机也能跑(flutter test),是"界面真能渲染 + 切歌真能切"的快速证据。
//
// 注:SoLoud 的原生库(libflutter_soloud_plugin.so)在 flutter test 无头环境里加载不了,
// _initAudio 会把这个异常 catch 掉、只打一条日志,不影响界面。所以这里只验证界面/切歌,
// 不碰音频路径(音频得装机听)。
//
// 断言只查"歌名标题"和"和弦名"这类稳定的东西——不查具体歌词短语:第12步起歌词按词渲染
// (每个词一个 Text,好让和弦浮在具体词上方),像 "way up high" 这种短语会拆成 3 个 Text,
// 用 textContaining 找整串会扑空。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ukulele_demo/main.dart';
import 'package:ukulele_demo/screens/chord_library_screen.dart';
import 'package:ukulele_demo/screens/stats_screen.dart';
import 'package:ukulele_demo/widgets/chord_diagram.dart';

void main() {
  // widget 测试里 SharedPreferences 的平台通道没接,getInstance() 会挂住不返回;
  // 给个空 mock 库,读出来都是默认值(跟单元测试 prefs_test 同一套路)。
  // 也让 SongScreen._loadPrefs / StatsScreen._load 能正常完成、不卡 pumpAndSettle。
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('默认显示第一首歌', (tester) async {
    await tester.pumpWidget(const UkuleleApp());

    // 顶栏下拉框当前显示第一首的歌名
    expect(find.textContaining('Somewhere Over the Rainbow'), findsOneWidget);
    // 这首歌用到的 Am 和弦贴片在界面上
    expect(find.text('Am'), findsWidgets);
  });

  testWidgets('下拉框能切换到第二首歌', (tester) async {
    await tester.pumpWidget(const UkuleleApp());
    // 起点确认是第一首
    expect(find.textContaining('Somewhere Over the Rainbow'), findsOneWidget);

    // 点顶栏歌名下拉框,打开列表
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();

    // 在展开的列表里点第二首(列表项;用 .last 取列表里那一项,避开可能的重复)
    await tester.tap(find.textContaining('What a Wonderful World').last);
    await tester.pumpAndSettle();

    // 切完后顶栏变成第二首的歌名
    expect(find.textContaining('What a Wonderful World'), findsOneWidget);
  });

  testWidgets('下拉框里有新加的 3 首歌', (tester) async {
    await tester.pumpWidget(const UkuleleApp());
    // 点开顶栏下拉框
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();

    // 第20步新追加的 3 首歌都在列表里(用已有和弦 C/G/Am/F/D/Em,不动音频)
    expect(find.textContaining('Hey Soul Sister'), findsOneWidget);
    expect(find.textContaining('Zombie'), findsOneWidget);
    expect(find.textContaining('Counting Stars'), findsOneWidget);
  });

  testWidgets('底导航能切到和弦页', (tester) async {
    await tester.pumpWidget(const UkuleleApp());
    await tester.pumpAndSettle();

    // 点底导航"和弦"
    await tester.tap(find.text('和弦'));
    await tester.pumpAndSettle();

    // 底导航当前选中 = 和弦(index 1)
    final bnb1 = tester.widget<BottomNavigationBar>(
      find.byType(BottomNavigationBar),
    );
    expect(bnb1.currentIndex, 1);
    // 和弦页挂在树里:AppBar 标题 + 指法图
    expect(find.byType(ChordLibraryScreen), findsOneWidget);
    expect(find.text('和弦速查'), findsOneWidget);
    expect(find.byType(ChordDiagram), findsWidgets);
  });

  testWidgets('底导航能切到统计页', (tester) async {
    await tester.pumpWidget(const UkuleleApp());
    await tester.pumpAndSettle();

    // 点底导航"统计"
    await tester.tap(find.text('统计'));
    await tester.pumpAndSettle();

    // 底导航当前选中 = 统计(index 2)
    final bnb2 = tester.widget<BottomNavigationBar>(
      find.byType(BottomNavigationBar),
    );
    expect(bnb2.currentIndex, 2);
    // 统计页挂在树里:有"全部练习"总计卡 + "按歌曲"分组标题
    expect(find.byType(StatsScreen), findsOneWidget);
    expect(find.text('全部练习'), findsOneWidget);
    expect(find.text('按歌曲'), findsOneWidget);
  });
}
