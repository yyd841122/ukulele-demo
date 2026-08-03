// 尤克里里弹唱练习 —— Flutter 版主入口 + 歌曲页。
//
// 这一版:歌曲页展示"歌词 + 和弦",顶栏下拉框选歌,底部 ▶ 按一下就按 BPM 嗒嗒响(节拍器)。
// 每一组(beatsPerChord 拍)的第 1 拍是高音重音,帮新手找准"第 1 拍"不跟丢。
// 还没做:和弦跟着拍子高亮、自动滚动。
import 'dart:async'; // Timer(定时器)在这

import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart'; // 低延迟音频引擎,专为短音效/快速重复播设计

import 'models.dart';

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

/// 歌曲页:顶栏下拉选歌,正文铺出当前歌的每一段、每一行。
/// 因为要"记住当前选的是哪首",这里用 StatefulWidget(带状态),
/// 之前只显示一首时用的是 StatelessWidget。
class SongScreen extends StatefulWidget {
  const SongScreen({super.key});

  @override
  State<SongScreen> createState() => _SongScreenState();
}

class _SongScreenState extends State<SongScreen> {
  // 当前选中的歌在 songs 列表里的下标。默认第 0 首(Over the Rainbow)。
  int _selected = 0;

  // —— 节拍器状态 ——
  // _playing:现在正在打拍子吗;_timer:每隔多久响一次的"闹钟";_player:播放嗒声的播放器。
  bool _playing = false;
  // 当前是这一组里的第几拍(0 = 第 1 拍 = 要播重音)。一组几拍由歌曲的 beatsPerChord 决定。
  int _beat = 0;
  Timer? _timer;

  // SoLoud:把两个嗒声各加载成一个"声源(AudioSource)"。每拍 play(src) 起一个全新实例从头播 →
  // 低延迟、每次从头响、连播不会变小声、第一拍也不会被吞(专为这种场景设计)。
  AudioSource? _normalSrc; // 普通"嗒"
  AudioSource? _accentSrc; // 高音重音
  bool _ready = false; // 引擎和音频都加载好了吗(没好之前 ▶ 按钮变灰、按了也不出声)

  @override
  void initState() {
    super.initState();
    _initAudio(); // 后台初始化引擎 + 加载两个音频(不 await,不卡界面)
  }

  /// 初始化 SoLoud 引擎、把两个嗒声各加载成一个声源。加载好后 _ready=true。
  Future<void> _initAudio() async {
    try {
      await SoLoud.instance.init();
      _normalSrc = await SoLoud.instance.loadAsset('assets/click.wav');
      _accentSrc = await SoLoud.instance.loadAsset('assets/click_accent.wav');
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (e) {
      // 万一加载失败,这条会进 logcat,方便排查。
      debugPrint('音频初始化失败: $e');
    }
  }

  @override
  void dispose() {
    // 页面销毁时收尾:停闹钟、释放两个声源,否则占资源。
    _timer?.cancel();
    if (_normalSrc != null) SoLoud.instance.disposeSource(_normalSrc!);
    if (_accentSrc != null) SoLoud.instance.disposeSource(_accentSrc!);
    super.dispose();
  }

  /// 两拍之间的间隔。BPM = 每分钟多少拍,所以一拍 = 60000毫秒 ÷ BPM。
  /// 例:72 BPM → 60000/72 ≈ 833 毫秒一拍。
  Duration get _beatInterval =>
      Duration(milliseconds: (60000 / songs[_selected].tempo).round());

  /// 按一下 ▶/⏸:正在响就停,没响就开始。
  void _togglePlay() {
    if (_playing) {
      _timer?.cancel();
      _timer = null;
    } else {
      _beat = 0; // 从第 1 拍开始
      _playClick(accent: true); // 第 1 拍重音,立刻响,不用干等一个间隔。
      _timer = Timer.periodic(_beatInterval, (_) {
        // 每响一声前进一拍;数到一组末尾(beatsPerChord)就归零,回到第 1 拍重音。
        _beat = (_beat + 1) % songs[_selected].beatsPerChord;
        _playClick(accent: _beat == 0);
      });
    }
    setState(() => _playing = !_playing);
  }

  /// 换歌:速度可能变了,先停掉节拍器,免得还按上一首的旧速度响。
  void _onSongChanged(int i) {
    _timer?.cancel();
    _timer = null;
    setState(() {
      _playing = false;
      _selected = i;
    });
  }

  /// 播一声。play(src) 每次起一个全新实例从头播 → 低延迟、每次从头响、连播不会变小声。
  /// accent=true 播高音重音(第 1 拍),否则普通嗒。引擎还没加载好时 src 为 null,跳过。
  void _playClick({bool accent = false}) {
    final src = accent ? _accentSrc : _normalSrc;
    if (src != null) SoLoud.instance.play(src);
  }

  @override
  Widget build(BuildContext context) {
    final song = songs[_selected];
    final theme = Theme.of(context);

    // 把"段落标题(可选)+ 它的每一行"拍平成一个列表,丢进可滚动的 ListView。
    final List<Widget> items = [];
    for (final section in song.sections) {
      if (section.name != null) {
        items.add(_SectionHeader(section.name!));
      }
      for (final line in section.lines) {
        items.add(_LineView(line: line));
      }
    }

    return Scaffold(
      appBar: AppBar(
        // 标题行:选歌下拉框(独占整行宽度,不再和 BPM 抢,就不会重叠出斑马纹)。
        title: DropdownButton<int>(
          value: _selected,
          // 下拉框默认会在选中值下面画一条横线,顶栏里很难看,这里用空部件去掉。
          underline: const SizedBox.shrink(),
          // 让下拉框占满整行宽度:歌名才有地方放,而且下面的 FittedBox 才知道往多窄缩。
          isExpanded: true,
          items: [
            for (var i = 0; i < songs.length; i++)
              DropdownMenuItem(
                value: i,
                // FittedBox(scaleDown):歌名短就原样大小;太长就自动缩小字号塞进去,绝不溢出。
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    songs[i].title,
                    style: TextStyle(color: theme.colorScheme.onSurface),
                  ),
                ),
              ),
          ],
          onChanged: (i) {
            if (i != null) _onSongChanged(i);
          },
          dropdownColor: theme.colorScheme.surface,
          // 下面这个 style 是"下拉框里当前显示的那行歌名"的文字样式。
          style: theme.textTheme.titleMedium
              ?.copyWith(color: theme.colorScheme.onSurface),
          icon: Icon(Icons.arrow_drop_down, color: theme.colorScheme.onSurface),
        ),
        // 第二行:速度信息。用 AppBar 的 bottom 槽放,跟标题各占一行,互不重叠。
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '${song.tempo} BPM · ${song.beatsPerChord}拍 · 第1拍重音',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: items,
      ),
      // 右下角大圆按钮:▶ 开始打拍 / ⏸ 停。节拍器的总开关。
      // 音频还没加载好时 onPressed=null,按钮变灰按不动;加载好(几乎瞬间)就能用。
      floatingActionButton: FloatingActionButton(
        onPressed: _ready ? _togglePlay : null,
        child: Icon(_playing ? Icons.pause : Icons.play_arrow),
      ),
    );
  }
}

/// 段落标题(如"🎶 副歌")。下划线开头 = 这个部件只在本文件内用。
class _SectionHeader extends StatelessWidget {
  final String name;

  const _SectionHeader(this.name);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(
        name,
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 一行:上面一排和弦贴片,下面是歌词。
class _LineView extends StatelessWidget {
  final Line line;

  const _LineView({required this.line});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 和弦行:每个和弦一个小贴片。用 Wrap 是为了窄屏(手机)能自动换行,不会溢出报错。
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [for (final c in line.chords) _ChordChip(c)],
          ),
          const SizedBox(height: 4),
          // 歌词
          Text(line.lyric, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}

/// 单个和弦贴片:圆角小色块 + 和弦名。
class _ChordChip extends StatelessWidget {
  final String chord;

  const _ChordChip(this.chord);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.primary, width: 1),
      ),
      child: Text(
        chord,
        style: TextStyle(
          color: cs.onPrimaryContainer,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }
}
