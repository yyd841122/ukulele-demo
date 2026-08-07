// 第47步:ThemeController 无头测试——默认 system、set 改值 + 持久化、init 读回上次选的。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ukulele_demo/prefs/app_preferences.dart';
import 'package:ukulele_demo/theme_controller.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('默认 = system;init 没存过也是 system', () async {
    final p = await AppPreferences.load();
    final c = ThemeController();
    expect(c.value, ThemeMode.system); // 构造默认
    await c.init(p); // 没存过 → 还是 system
    expect(c.value, ThemeMode.system);
  });

  test('set 改值 + 持久化 + notify:重启读回上次选的', () async {
    var p = await AppPreferences.load();
    final c = ThemeController();
    await c.init(p);
    ThemeMode? heard;
    c.addListener(() => heard = c.value);

    await c.set(ThemeMode.dark);
    expect(c.value, ThemeMode.dark);
    expect(heard, ThemeMode.dark); // notify 了(ValueListenableBuilder 靠它换肤)

    // 模拟重启:新控制器、同一份 prefs,init 读回 dark
    p = await AppPreferences.load();
    final c2 = ThemeController();
    await c2.init(p);
    expect(c2.value, ThemeMode.dark);
  });

  test('存过的浅色值跨 init 还原', () async {
    SharedPreferences.setMockInitialValues({'pref_theme_mode': 'light'});
    final p = await AppPreferences.load();
    final c = ThemeController();
    await c.init(p);
    expect(c.value, ThemeMode.light);
  });
}
