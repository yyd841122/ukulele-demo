// 主题控制器(第47步):持有当前 ThemeMode、持久化、通知 MaterialApp 换肤。
//
// 为什么单独一个类:UkuleleApp 用 ValueListenableBuilder 听它,mode 一变 MaterialApp 就换 themeMode;
// 统计页顶栏的切换菜单也调它.set()。换肤时 home 是同一个 MainScaffold 实例,靠 Flutter 树复用,
// _MainScaffoldState(音频引擎 / 节拍器 / 歌库)不重置——切主题不会把正在练的节拍器打断。
import 'package:flutter/material.dart';

import 'prefs/app_preferences.dart';

class ThemeController extends ValueNotifier<ThemeMode> {
  AppPreferences? _prefs;

  ThemeController() : super(ThemeMode.system); // 默认跟系统;init 后读回上次选的

  /// 启动时读回上次选的(UkuleleApp 拿到 prefs 后调一次)。
  Future<void> init(AppPreferences p) async {
    _prefs = p;
    value = _fromString(p.getThemeMode());
  }

  /// 切模式、持久化、notify(MaterialApp 跟着换)。
  Future<void> set(ThemeMode mode) async {
    value = mode;
    await _prefs?.setThemeMode(_toString(mode));
  }

  static ThemeMode _fromString(String s) => switch (s) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
  static String _toString(ThemeMode m) => switch (m) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };
}
