// 尤克里里弹唱练习 —— Flutter 版主入口。
//
// 这里只放 main() + UkuleleApp(根部件:决定主题、把"歌曲页"设为首页)。
// 真正的东西拆在别处(第19步重构):
//   - screens/song_screen.dart :歌曲页 + 节拍器引擎(状态都在这)
//   - widgets/                 :练习栏 / 和弦指法图 / 歌词行 等界面部件
//   - audio/                   :音频引擎(SoLoud)+ 扫弦合成
//   - prefs/                   :持久化(记住上次的歌 / 速度 / 节奏型 / AB 区间)
//   - models.dart              :数据模型(歌曲 / 和弦 / 节奏型 / 歌曲库)
// 测试 test/widget_test.dart import 的是这个文件 + UkuleleApp,所以这两样留在 main.dart 里不动。
import 'package:flutter/material.dart';

import 'screens/song_screen.dart';

void main() {
  runApp(const UkuleleApp());
}

/// App 根部件:决定主题,把"歌曲页"设为首页。
class UkuleleApp extends StatelessWidget {
  const UkuleleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '尤克里里弹唱练习',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // 深色主题,观感对齐 Web 版 PWA;seedColor 决定整体配色基调。
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C8EE3), // 偏蓝紫,呼应"彩虹"主题
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const SongScreen(),
    );
  }
}
