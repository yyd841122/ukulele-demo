// 主框架:底导航 4 个 tab(首页 / 练琴 / 和弦 / 统计)+ 共享音频引擎。
//
// 第N步(UI 重构):原来 7 个 tab 太挤,合并成 4 个:
//   - 「练琴」tab 把原来的 练习 / 换和弦 / 指弹 / 琶音 4 个收拢成 Hub,点卡片全屏 push 进去。
//   - 「调音」从底栏移除,改成首页快捷卡片(push)。需要调音时从首页进。
//   - 新增「首页」作第一屏(_index 初值 0):聚合入口 + 今日仪表盘。
//
// IndexedStack 保活 4 个 tab。原来"切走 tab 时戳练习页 stop / flushStats / 调音 pause"那套钩子
// 全删了——练习页现在是 Hub 里 push 上来的全屏页,pop 时 dispose() 自动清理(节拍器 / 录音 /
// wakelock / 统计落盘),调音页 dispose() 也自动停麦。只剩"进统计 tab 让它 reload 重读 prefs"。
import 'package:flutter/material.dart';

import 'audio/audio_engine.dart';
import 'prefs/app_preferences.dart';
import 'screens/chord_library_screen.dart';
import 'screens/home_screen.dart';
import 'screens/practice_hub_screen.dart';
import 'screens/stats_screen.dart';
import 'song_store.dart';
import 'theme_controller.dart';

/// 主框架:底导航 + 共享 AudioEngine。UkuleleApp 的 home 指向它。
class MainScaffold extends StatefulWidget {
  // 主题控制器:从根传进来,再透给统计页(和首页)的切换菜单。
  final ThemeController theme;

  const MainScaffold({required this.theme, super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  // 各 tab 共用的音频引擎(嗒声 + 扫弦声)。本页拥有 / init / dispose;各 tab 收引用、只调方法。
  final AudioEngine _audio = AudioEngine();

  // 歌单(内置歌 + 用户自加歌)。构造时内置歌就位(界面第一帧有歌);用户歌 _initSongs() 后追加。
  // 加 / 删用户歌时它 notify,练琴 Hub / 统计页跟着刷新。
  final SongStore _songs = SongStore();

  // 统计页 key:进统计 tab 时调 reload() 重读最新 prefs(打卡 / 今日进度)。
  final GlobalKey<StatsScreenState> _statsKey = GlobalKey<StatsScreenState>();

  int _index = 0; // 当前选中第几个 tab(0 首页 / 1 练琴 / 2 和弦 / 3 统计)

  @override
  void initState() {
    super.initState();
    _initAudio(); // 后台初始化引擎 + 加载音频(不 await,不卡界面)
    _initSongs(); // 后台加载用户自加的歌、追加到内置歌后面
  }

  /// 后台加载用户自加的歌(读 prefs JSON),追加到内置歌后面。有用户歌才 notify,练琴 / 统计页跟着刷新。
  Future<void> _initSongs() async {
    final p = await AppPreferences.load();
    if (!mounted) return;
    await _songs.load(p);
  }

  /// 后台初始化音频引擎。失败(如测试环境加载不了原生库)引擎内部 catch 打日志;不点亮 ▶ 即可。
  /// init 完 setState 一下:子页 build 里读 widget.audio.isReady 才会从 false 翻 true。
  Future<void> _initAudio() async {
    await _audio.init();
    if (!mounted) return;
    setState(() {});
  }

  /// 切 tab(底栏点 / 首页快捷卡片都走这里)。进统计 tab 让它 reload 重读最新 prefs。
  void _onTabTapped(int i) {
    setState(() => _index = i);
    if (i == 3) {
      // 统计 tab:IndexedStack 保活,initState 只跑一次,这里手动让它重读最新 prefs。
      _statsKey.currentState?.reload();
    }
  }

  @override
  void dispose() {
    _audio.dispose(); // app 退出时释放声源(各 tab / push 页不各自释放,统一在这)
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack 保活:切 tab 不重建子页。
      body: IndexedStack(
        index: _index,
        children: [
          HomeScreen(audio: _audio, onNavigate: _onTabTapped),
          PracticeHubScreen(audio: _audio, store: _songs),
          ChordLibraryScreen(audio: _audio),
          StatsScreen(key: _statsKey, store: _songs, theme: widget.theme),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        // fixed:选中/未选中的 label 都常显(4 个 tab 默认会变 shifting)。
        type: BottomNavigationBarType.fixed,
        currentIndex: _index,
        onTap: _onTabTapped,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: '首页'),
          BottomNavigationBarItem(icon: Icon(Icons.music_note), label: '练琴'),
          BottomNavigationBarItem(icon: Icon(Icons.library_music_outlined), label: '和弦'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart_outlined), label: '统计'),
        ],
      ),
    );
  }
}
