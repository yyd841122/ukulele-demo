// 主框架:底导航(练习 / 和弦 / 统计)+ 共享音频引擎。
// 第28步新建——把原来全挂在 SongScreen 顶栏的功能(统计、和弦速查)挪成平级 tab,
// 并把 AudioEngine 上提到这里统一拥有 / 初始化:多个 tab 共用一份引擎,避免二次 init SoLoud。
//
// IndexedStack 保活所有 tab:切到别的 tab 时练习页的节拍器状态(_playing / _idx / _timer 等)不丢,
// 切回来接着用。代价是所有 tab 一次都挂上(各 initState 启动时跑一遍),这几个页都轻,没问题。
//
// 数据新鲜度:统计 tab 和练习 tab 平级后,不再靠"进页前 push"刷盘。所以切走练习 tab 时主动调
// 练习页的 flushStats()(把当前会话打卡落盘)、切到统计 tab 时调它的 reload()(重读 prefs)——
// 统计页才读得到含本次练习的最新值。
import 'package:flutter/material.dart';

import 'audio/audio_engine.dart';
import 'screens/chord_library_screen.dart';
import 'screens/song_screen.dart';
import 'screens/stats_screen.dart';
import 'screens/tuner_screen.dart';

/// 主框架:底导航 + 共享 AudioEngine。UkuleleApp 的 home 指向它(替原来的 SongScreen)。
class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  // 各 tab 共用的音频引擎(嗒声 + 扫弦声)。本页拥有 / init / dispose;各 tab 收引用、只调方法。
  final AudioEngine _audio = AudioEngine();

  // 练习页 / 统计页的 key:用来在切 tab 时"戳一下"它们的状态(flushStats / reload)。
  final GlobalKey<SongScreenState> _songKey = GlobalKey<SongScreenState>();
  final GlobalKey<StatsScreenState> _statsKey = GlobalKey<StatsScreenState>();

  int _index = 0; // 当前选中第几个 tab(0 练习 / 1 和弦 / 2 统计 / 3 调音)

  @override
  void initState() {
    super.initState();
    _initAudio(); // 后台初始化引擎 + 加载音频(不 await,不卡界面)
  }

  /// 后台初始化音频引擎。失败(如测试环境加载不了原生库)引擎内部 catch 打日志;不点亮 ▶ 即可。
  /// init 完 setState 一下:子页 build 里读 widget.audio.isReady 才会从 false 翻 true。
  Future<void> _initAudio() async {
    await _audio.init();
    if (!mounted) return;
    setState(() {});
  }

  /// 切 tab。离开练习 tab(0→别的)时先把当前会话打卡刷盘(统计 tab 才读得到最新);
  /// 进统计 tab 时让它 reload 重读。两个戳都靠 key 找到对应 State,空安全。
  void _onTabTapped(int i) {
    final leavingPractice = _index == 0 && i != 0;
    setState(() => _index = i);
    if (leavingPractice) {
      _songKey.currentState?.flushStats();
    }
    if (i == 2) {
      // 统计 tab:tab 平级后 initState 只跑一次,这里手动让它重读最新 prefs。
      _statsKey.currentState?.reload();
    }
  }

  @override
  void dispose() {
    _audio.dispose(); // app 退出时释放声源(各 tab 不各自释放,统一在这)
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack 保活:切 tab 不重建子页,练习页节拍器状态不丢。
      body: IndexedStack(
        index: _index,
        children: [
          SongScreen(key: _songKey, audio: _audio),
          ChordLibraryScreen(audio: _audio),
          StatsScreen(key: _statsKey),
          TunerScreen(audio: _audio),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        // fixed:选中/未选中的 label 都常显。底导航有 4 个 tab,默认会变 shifting(label 忽隐忽现),
        // 显式 fixed 让 4 个 label 都常显。
        type: BottomNavigationBarType.fixed,
        currentIndex: _index,
        onTap: _onTabTapped,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.music_note_outlined),
            label: '练习',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.library_music_outlined),
            label: '和弦',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart_outlined),
            label: '统计',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.graphic_eq_outlined),
            label: '调音',
          ),
        ],
      ),
    );
  }
}
