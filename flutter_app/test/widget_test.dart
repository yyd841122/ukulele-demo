// 界面测试:首页是第一屏、底导航 4 个 tab 能切、练琴 Hub 选模式能 push 进练习页、首页能 push 进调音页。
//
// 这一步不连手机也能跑(flutter test),是"界面真能渲染 + 导航真能切"的快速证据。
//
// 注:SoLoud 的原生库(libflutter_soloud_plugin.so)在 flutter test 无头环境里加载不了,
// _initAudio 会把这个异常 catch 掉、只打一条日志,不影响界面。所以这里只验证界面/导航,
// 不碰音频路径(音频得装机听)。
//
// 断言只查稳定的东西(卡片标题、歌名、和弦名)——不查具体歌词短语:歌词按词渲染(每个词一个 Text),
// 像 "way up high" 这种短语会拆成多个 Text,textContaining 找整串会扑空。
//
// 第N步(UI 重构):底栏从 7 个 tab 改成 4 个(首页/练琴/和弦/统计);调音 / 换和弦 / 指弹 / 琶音
// 不再是 tab,改成从首页卡片(push 调音)或练琴 Hub(push 4 种练习)进入。本文件按新结构重写。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ukulele_demo/main.dart';
import 'package:ukulele_demo/screens/chord_library_screen.dart';
import 'package:ukulele_demo/screens/home_screen.dart';
import 'package:ukulele_demo/screens/onboarding_screen.dart';
import 'package:ukulele_demo/screens/practice_hub_screen.dart';
import 'package:ukulele_demo/screens/song_screen.dart';
import 'package:ukulele_demo/screens/stats_screen.dart';
import 'package:ukulele_demo/screens/tuner_screen.dart';

void main() {
  // widget 测试里 SharedPreferences 的平台通道没接,getInstance() 会挂住不返回;
  // 给个空 mock 库,读出来都是默认值(跟单元测试 prefs_test 同一套路)。
  // 也让 SongScreen._loadPrefs / StatsScreen._load 能正常完成、不卡 pumpAndSettle。
  setUp(() {
    // 默认标记新手引导已完成:别的测试不弹引导盖住首页。引导专属测试在自己开头覆盖。
    SharedPreferences.setMockInitialValues({'pref_onboarding_done': true});
  });

  // 底栏 tab 的 label 也会作为 Text 出现在树里(首页卡片标题可能撞名),用 descendant 精确戳底栏那个。
  Finder navItem(String label) => find.descendant(
        of: find.byType(BottomNavigationBar),
        matching: find.text(label),
      );

  // 从首页一路进到「扫弦跟唱」练习页:切练琴 tab → 点扫弦跟唱卡片(push SongScreen)。
  Future<void> openSongScreen(WidgetTester tester) async {
    await tester.pumpWidget(const UkuleleApp());
    await tester.pumpAndSettle();
    await tester.tap(navItem('练琴'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('扫弦跟唱'));
    await tester.pumpAndSettle();
  }

  testWidgets('默认进入首页(不是练习页)', (tester) async {
    await tester.pumpWidget(const UkuleleApp());
    await tester.pumpAndSettle();

    // 首页挂在树里、底栏选中 = 首页(index 0)
    expect(find.byType(HomeScreen), findsOneWidget);
    final bnb = tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
    expect(bnb.currentIndex, 0);
    // 首页快捷卡片在(调音卡片标题——调音已不在底栏,只在首页;「练琴」既在底栏也在首页卡片,避开它)
    expect(find.text('调音'), findsOneWidget);
    expect(find.text('今日练习'), findsOneWidget); // 今日仪表盘卡标题
  });

  testWidgets('底导航能切到练琴页(Hub)', (tester) async {
    await tester.pumpWidget(const UkuleleApp());
    await tester.pumpAndSettle();

    await tester.tap(navItem('练琴'));
    await tester.pumpAndSettle();

    expect(find.byType(PracticeHubScreen), findsOneWidget);
    final bnb = tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
    expect(bnb.currentIndex, 1);
    // 4 张练习方式卡片都在
    expect(find.text('扫弦跟唱'), findsOneWidget);
    expect(find.text('换和弦'), findsOneWidget);
    expect(find.text('指弹'), findsOneWidget);
    expect(find.text('琶音'), findsOneWidget);
  });

  testWidgets('底导航能切到和弦页', (tester) async {
    await tester.pumpWidget(const UkuleleApp());
    await tester.pumpAndSettle();

    await tester.tap(navItem('和弦'));
    await tester.pumpAndSettle();

    final bnb = tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
    expect(bnb.currentIndex, 2);
    expect(find.byType(ChordLibraryScreen), findsOneWidget);
    expect(find.text('和弦速查'), findsOneWidget);
  });

  testWidgets('底导航能切到统计页', (tester) async {
    await tester.pumpWidget(const UkuleleApp());
    await tester.pumpAndSettle();

    await tester.tap(navItem('统计'));
    await tester.pumpAndSettle();

    final bnb = tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
    expect(bnb.currentIndex, 3);
    expect(find.byType(StatsScreen), findsOneWidget);
    expect(find.text('全部练习'), findsOneWidget);
    expect(find.textContaining('连续'), findsOneWidget);
  });

  testWidgets('练琴 Hub 点扫弦跟唱进入练习页', (tester) async {
    await openSongScreen(tester);

    // SongScreen 被 push 上来了,默认显示第一首歌
    expect(find.byType(SongScreen), findsOneWidget);
    expect(find.textContaining('Somewhere Over the Rainbow'), findsOneWidget);
  });

  testWidgets('练习页下拉框能切换到第二首歌', (tester) async {
    await openSongScreen(tester);
    expect(find.textContaining('Somewhere Over the Rainbow'), findsOneWidget);

    // 点顶栏歌名下拉框,打开列表
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();

    // 在展开的列表里点第二首(.last 取列表里那一项,避开可能的重复)
    await tester.tap(find.textContaining('What a Wonderful World').last);
    await tester.pumpAndSettle();

    // 切完后顶栏变成第二首的歌名
    expect(find.textContaining('What a Wonderful World'), findsOneWidget);
  });

  testWidgets('首页点调音卡片进入调音页', (tester) async {
    await tester.pumpWidget(const UkuleleApp());
    await tester.pumpAndSettle();

    // 首页点「调音」卡片 → push 调音页(卡片可能在矮测试画布上要滚一下才可见)
    await tester.ensureVisible(find.text('调音'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('调音'));
    await tester.pumpAndSettle();

    expect(find.byType(TunerScreen), findsOneWidget);
    // 四根弦的按钮都在
    expect(find.text('G 弦'), findsOneWidget);
    expect(find.text('C 弦'), findsOneWidget);
    expect(find.text('E 弦'), findsOneWidget);
    expect(find.text('A 弦'), findsOneWidget);
    // A 弦频率显示(440.00 Hz)+ 校准行
    expect(find.textContaining('440.00'), findsOneWidget);
    expect(find.textContaining('基准音 A4'), findsOneWidget);
  });

  testWidgets('和弦页搜索框过滤和弦', (tester) async {
    await tester.pumpWidget(const UkuleleApp());
    await tester.pumpAndSettle();
    await tester.tap(navItem('和弦'));
    await tester.pumpAndSettle();

    // 初始:大三类的 C 在(靠顶,可见)
    expect(find.text('C'), findsWidgets);

    // 搜 sus4 → 只剩挂四类(5 个都进视口);纯 C 被过滤
    await tester.enterText(
      find.descendant(of: find.byType(ChordLibraryScreen), matching: find.byType(TextField)),
      'sus4',
    );
    await tester.pumpAndSettle();
    expect(find.text('Csus4'), findsOneWidget);
    expect(find.text('C'), findsNothing);
  });

  testWidgets('和弦页类别筛选只显示该类', (tester) async {
    await tester.pumpWidget(const UkuleleApp());
    await tester.pumpAndSettle();
    await tester.tap(navItem('和弦'));
    await tester.pumpAndSettle();

    // 点「小三」chip
    await tester.tap(find.text('小三'));
    await tester.pumpAndSettle();

    // 小三和弦 Am 在,大三和弦 C 不在
    expect(find.text('Am'), findsOneWidget);
    expect(find.text('C'), findsNothing);
  });

  testWidgets('扫弦页难度筛选:点入门→只显入门歌并跳到第一首(完善Step4)', (tester) async {
    await openSongScreen(tester);
    // 默认显示第一首 Rainbow(初级),下拉框里也能看到它的难度标签「初级」
    expect(find.textContaining('Somewhere Over the Rainbow'), findsOneWidget);

    // 点「入门(N)」难度筛选芯片
    await tester.tap(find.textContaining('入门('));
    await tester.pumpAndSettle();

    // 筛后自动跳到第一首入门歌 = You Are My Sunshine(C G)
    expect(find.textContaining('You Are My Sunshine'), findsOneWidget);
    // Rainbow 是初级、被筛掉了,折叠的下拉框里不再出现
    expect(find.textContaining('Somewhere Over the Rainbow'), findsNothing);
  });

  testWidgets('新手引导:首启没完成过→自动弹,跳过后关掉(完善Step6)', (tester) async {
    SharedPreferences.setMockInitialValues({}); // 没完成引导
    await tester.pumpWidget(const UkuleleApp());
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsOneWidget);

    // 点「跳过」→ 标记完成 + 关页
    await tester.tap(find.text('跳过'));
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsNothing);
  });

  testWidgets('新手引导:完成过→不再自动弹,直接进首页(完善Step6)', (tester) async {
    SharedPreferences.setMockInitialValues({'pref_onboarding_done': true});
    await tester.pumpWidget(const UkuleleApp());
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('首页「?」入口能重看新手引导(完善Step6)', (tester) async {
    SharedPreferences.setMockInitialValues({'pref_onboarding_done': true});
    await tester.pumpWidget(const UkuleleApp());
    await tester.pumpAndSettle();
    final help = find.byTooltip('新手指南');
    expect(help, findsOneWidget);
    await tester.tap(help);
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsOneWidget);
  });
}
