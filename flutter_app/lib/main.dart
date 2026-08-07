// 尤克里里弹唱练习 —— Flutter 版主入口。
//
// 这里只放 main() + UkuleleApp(根部件:决定主题、把"主框架"设为首页)。
// 真正的东西拆在别处(第19步重构 / 第28步加底导航 / 第47步浅深色主题):
//   - main_scaffold.dart        :主框架(底导航 + 共享 AudioEngine),home 指向它
//   - theme_controller.dart     :主题控制器(系统 / 浅色 / 深色,持久化 + 通知换肤)
//   - screens/song_screen.dart  :练习页 + 节拍器引擎(状态都在这)
//   - screens/                  :和弦速查 / 练习统计 等其它 tab 页
//   - widgets/                  :练习栏 / 和弦指法图 / 歌词行 等界面部件
//   - audio/                    :音频引擎(SoLoud)+ 扫弦合成
//   - prefs/                    :持久化(记住上次的歌 / 速度 / 节奏型 / AB 区间 / 主题)
//   - models.dart               :数据模型(歌曲 / 和弦 / 节奏型 / 歌曲库)
// 测试 test/widget_test.dart import 的是这个文件 + UkuleleApp,所以这两样留在 main.dart 里不动。
import 'package:flutter/material.dart';

import 'main_scaffold.dart';
import 'prefs/app_preferences.dart';
import 'theme_controller.dart';

void main() {
  runApp(const UkuleleApp());
}

/// App 根部件:决定主题(浅色 / 深色 / 跟系统),把"主框架"设为首页。
class UkuleleApp extends StatefulWidget {
  const UkuleleApp({super.key});

  @override
  State<UkuleleApp> createState() => _UkuleleAppState();
}

class _UkuleleAppState extends State<UkuleleApp> {
  // 主题控制器:持有当前 ThemeMode + 持久化 + 通知换肤。ValueListenableBuilder 听它。
  final ThemeController _theme = ThemeController();

  @override
  void initState() {
    super.initState();
    _initTheme(); // 后台读回上次选的主题(默认 system),不卡首帧
  }

  Future<void> _initTheme() async {
    final p = await AppPreferences.load();
    if (!mounted) return;
    await _theme.init(p);
  }

  @override
  Widget build(BuildContext context) {
    // ValueListenableBuilder:mode 一变就重建 MaterialApp 换 themeMode。home 是同一个 MainScaffold
    // 实例 → Flutter 树复用 → _MainScaffoldState(音频引擎 / 节拍器 / 歌库)不重置。
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _theme,
      builder: (context, mode, _) => MaterialApp(
        title: '尤克里里弹唱练习',
        debugShowCheckedModeBanner: false,
        // 浅色 + 深色两套,同一个蓝紫种子色(呼应"彩虹"主题);themeMode 决定用哪套。
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6C8EE3),
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6C8EE3),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        themeMode: mode,
        home: MainScaffold(theme: _theme),
      ),
    );
  }
}
