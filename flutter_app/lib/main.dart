// 尤克里里弹唱练习 —— Flutter 版主入口 + 歌曲页。
//
// 这一版:歌曲页展示"歌词 + 和弦",顶栏下拉框选歌,底部 ▶ 按一下就按 BPM 嗒嗒响(节拍器)。
// 节拍器一边打拍、一边把"当前和弦"按拍数往前推进:顶部练习栏显示现在弹哪个、扫到第几下、下一个是什么;
// 歌词里当前和弦贴片反色点亮、当前行微微高亮并自动滚到屏幕中间。播到末尾循环回开头。
// 还没做:和弦指法图(下一切片)。
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
/// 因为要"记住当前选的是哪首"+ 节拍器状态,这里用 StatefulWidget(带状态)。
class SongScreen extends StatefulWidget {
  const SongScreen({super.key});

  @override
  State<SongScreen> createState() => _SongScreenState();
}

class _SongScreenState extends State<SongScreen> {
  // 当前选中的歌在 songs 列表里的下标。默认第 0 首(Over the Rainbow)。
  int _selected = 0;

  // —— 节拍器状态 ——
  // _playing:现在正在打拍子吗;_timer:每隔多久响一次的"闹钟"。
  bool _playing = false;
  // 当前是这一组里的第几拍(0 = 第 1 拍 = 要播重音)。一组几拍由歌曲的 beatsPerChord 决定。
  int _beat = 0;
  // 当前按到"拍扁的和弦序列"里的第几个(0 = 第一个和弦)。每数够一组拍就前进一个。
  int _idx = 0;
  Timer? _timer;
  // 可调速度(BPM)。默认 = 当前歌的原速;拖练习栏的滑块能放慢来练。换歌时重置回原速。
  // 单独搞一个字段、不直接改 song.tempo:song.tempo 是"原速"这个只读事实,_tempo 才是"现在实际用多快"。
  late int _tempo;

  // —— 拍扁后的歌曲数据(换歌时重建)——
  // 这首歌所有和弦按顺序拍成一条线,跨所有行。例:[C, G, Am, F, C, G, Am, F, ...]
  List<String> _flat = [];
  // 和 _flat 等长:每个和弦属于第几行(用来知道该高亮哪行歌词、滚到哪行)。
  List<int> _lineOfChord = [];
  // 每一行歌词一个 GlobalKey,自动滚动时靠它定位"滚到这一行"。
  List<GlobalKey> _lineKeys = [];
  // 上一次高亮的是第几行;变了才滚动,避免每拍都抖一下。
  int _lastLine = 0;

  // SoLoud:把两个嗒声各加载成一个"声源(AudioSource)"。每拍 play(src) 起一个全新实例从头播 →
  // 低延迟、每次从头响、连播不会变小声、第一拍也不会被吞(专为这种场景设计)。
  AudioSource? _normalSrc; // 普通"嗒"
  AudioSource? _accentSrc; // 高音重音
  bool _ready = false; // 引擎和音频都加载好了吗(没好之前 ▶ 按钮变灰、按了也不出声)

  @override
  void initState() {
    super.initState();
    _rebuildFlat(); // 先把当前歌拍扁,界面第一次画就能显示"现在弹 第1个和弦"
    _tempo = songs[_selected].tempo; // 默认原速(late 字段必须在第一次被读之前赋上值)
    _initAudio(); // 后台初始化引擎 + 加载两个音频(不 await,不卡界面)
  }

  /// 把当前选中的歌拍扁成练习用的三个数组:_flat / _lineOfChord / _lineKeys。
  /// 对齐 Web 版 buildSong() 里的 flat / lineOfChord 逻辑(逐行、按出现顺序)。
  void _rebuildFlat() {
    final song = songs[_selected];
    _flat = [];
    _lineOfChord = [];
    final keys = <GlobalKey>[];
    var lineIdx = 0;
    for (final section in song.sections) {
      for (final line in section.lines) {
        keys.add(GlobalKey()); // 每行一个 key,自动滚动定位用
        for (final c in line.chords) {
          _flat.add(c);
          _lineOfChord.add(lineIdx);
        }
        lineIdx++;
      }
    }
    _lineKeys = keys;
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
  /// 例:72 BPM → 60000/72 ≈ 833 毫秒一拍。这里读 _tempo(可调),不读 song.tempo(原速)。
  Duration get _beatInterval =>
      Duration(milliseconds: (60000 / _tempo).round());

  /// 按一下 ▶/⏸:正在响就停,没响就接着弹。
  /// 对齐 Web:不归零、resume——暂停后再按 ▶ 接着上次停的地方继续;只有换歌才从头(见 _onSongChanged)。
  void _togglePlay() {
    if (_playing) {
      _timer?.cancel();
      _timer = null;
    } else {
      // 立刻响当前这一拍(第 1 次按就是 beat 0),不用干等一个间隔。
      _tick();
      // 之后每一拍:先推进到下一拍,再响+刷新。推进放前面,重画时读到的才是"正在响"的那拍。
      _timer = Timer.periodic(_beatInterval, (_) {
        _advance();
        _tick();
      });
    }
    setState(() => _playing = !_playing);
  }

  /// 换歌:速度可能变了,先停掉节拍器、把位置归零,再按新歌拍扁数据,免得还按上一首的旧结构走。
  void _onSongChanged(int i) {
    _timer?.cancel();
    _timer = null;
    setState(() {
      _playing = false;
      _selected = i;
      _idx = 0;
      _beat = 0;
      _tempo = songs[i].tempo; // 新歌用新歌的原速,免得还按上一首调出来的慢速走
      _rebuildFlat();
      _lastLine = _lineOfChord.isNotEmpty ? _lineOfChord[0] : 0;
    });
  }

  /// 拖滑块调速。正在播放时,旧 Timer.periodic 的间隔是【创建那一刻】就定死的、之后改 _tempo 它不知道,
  /// 所以必须 cancel 掉、用新的 _beatInterval 再起一个(下一拍就按新速度来)。
  /// 不归零位置(_idx/_beat 不动)、也不立刻补响一声——否则会跟刚才那拍叠在一起。
  /// 暂停时调也没事:只更新 _tempo,下次按 ▶ 自然用新速度。
  void _setTempo(int v) {
    if (v == _tempo) return;
    setState(() => _tempo = v);
    if (_playing) {
      _timer?.cancel();
      _timer = Timer.periodic(_beatInterval, (_) {
        _advance();
        _tick();
      });
    }
  }

  /// 走一拍:播当前这一拍的声音 + 刷新界面(练习栏、和弦贴片、当前行高亮)+ 该滚就滚。
  /// 这里【不】改 _beat/_idx —— 推进放 _advance() 里、在"下一拍"之前做。
  /// 因为 setState 是延迟到下一帧才重画的:若这边 setState 完就 +1,重画时读到的会是 +1 后的值,
  /// ↓ 会比声音快一拍(踩过的坑)。推进放前面就对了。
  void _tick() {
    _playClick(accent: _beat == 0); // 第 1 拍重音
    setState(() {}); // 刷新:练习栏、和弦贴片、当前行高亮
    _maybeScrollToCurrentLine();
  }

  /// 推进到下一拍:拍数 +1,到组末就进下一个和弦(末尾循环)。在每次 _tick 之前调。
  void _advance() {
    _beat++;
    final beatsPerChord = songs[_selected].beatsPerChord;
    if (_beat >= beatsPerChord) {
      _beat = 0;
      if (_flat.isNotEmpty) {
        _idx = (_idx + 1) % _flat.length; // 下一个和弦;到末尾循环回开头
      }
    }
  }

  /// 当前行变了,就把它滚到屏幕中间。每拍都调,但只有跨行才真滚,不会一拍一抖。
  void _maybeScrollToCurrentLine() {
    if (_flat.isEmpty || _idx >= _lineOfChord.length) return;
    final li = _lineOfChord[_idx];
    if (li == _lastLine) return;
    _lastLine = li;
    if (li >= _lineKeys.length) return;
    final ctx = _lineKeys[li].currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5, // 居中
        duration: const Duration(milliseconds: 250),
      );
    }
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

    // 把"段落标题 + 每一行"拍平成列表,同时数出每个和弦/每行的全局下标,
    // 用来标记"当前该高亮哪个和弦贴片、哪行歌词"。
    final List<Widget> items = [];
    final currentLine = (_flat.isEmpty || _idx >= _lineOfChord.length)
        ? 0
        : _lineOfChord[_idx];
    var chordCursor = 0; // 走到第几个和弦(全局)
    var lineCursor = 0; // 走到第几行(全局)
    for (final section in song.sections) {
      if (section.name != null) {
        items.add(_SectionHeader(section.name!));
      }
      for (final line in section.lines) {
        items.add(_LineView(
          line: line,
          lineKey: _lineKeys[lineCursor],
          isCurrentLine: lineCursor == currentLine,
          chordStart: chordCursor, // 这一行第 1 个和弦的全局下标
          currentChord: _idx,
        ));
        chordCursor += line.chords.length;
        lineCursor++;
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
              '$_tempo BPM${_tempo == song.tempo ? '' : (_tempo < song.tempo ? ' · 慢练' : ' · 加速')} · ${song.beatsPerChord}拍 · 第1拍重音',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // 顶部练习栏:吸顶(在可滚动歌词上方),显示"现在弹哪个、扫到第几下、下一个是什么"。
          _PracticeBar(
            chord: _flat.isEmpty ? '—' : _flat[_idx],
            beat: _beat,
            beatsPerChord: song.beatsPerChord,
            nextChord:
                _flat.isEmpty ? '—' : _flat[(_idx + 1) % _flat.length],
            tempo: _tempo,
            minTempo: (song.tempo / 2).round(), // 最慢到原速一半
            maxTempo: (song.tempo * 2).round(), // 最快到原速两倍——放开加速练
            onTempoChanged: _setTempo,
          ),
          // 歌词区:可滚动,当前行会自动滚到屏幕中间。
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: items,
            ),
          ),
        ],
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

/// 一行歌词:每个词一个单元,横向排开、自动换行。
/// 有和弦的词:上方浮和弦贴片;没和弦的词:纯文字(不留空、连贯)。
/// 所有词底部对齐(同一基线)。每个和弦词的单元至少和它的贴片一样宽,
/// 所以短词(如 "[C]I [G]watch" 里的 I)后面会自动多出间隙 → 和弦有地方放、不会叠、也不用错开。
/// 间隙不固定,由和弦宽度和词长决定(目标是练习弹奏:和弦该在哪、词就给哪腾地方)。
/// lineKey 定位自动滚动;isCurrentLine 时整行加底色;chordStart+currentChord 判断当前和弦。
class _LineView extends StatelessWidget {
  final Line line;
  final GlobalKey lineKey;
  final bool isCurrentLine;
  final int chordStart; // 这一行第 1 个和弦在全局 _flat 里的下标
  final int currentChord; // 当前全局和弦下标(_idx)

  const _LineView({
    required this.line,
    required this.lineKey,
    required this.isCurrentLine,
    required this.chordStart,
    required this.currentChord,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final units = parseWords(line.lyric);
    var localChord = 0; // 这一行里数到第几个和弦
    final children = <Widget>[];
    for (final u in units) {
      final isCurrent = u.hasChord && chordStart + localChord == currentChord;
      if (u.hasChord) localChord++;
      children.add(
        _WordUnitView(chord: u.chord, word: u.word, isCurrent: isCurrent),
      );
    }
    return Container(
      key: lineKey,
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
      decoration: BoxDecoration(
        color: isCurrentLine ? cs.primaryContainer.withValues(alpha: 0.3) : null,
        borderRadius: BorderRadius.circular(6),
      ),
      // Wrap:词单元横向排开、窄屏自动换行。crossAxisAlignment=end → 所有词同基线,
      // 和弦只浮在"有和弦的词"上方(没和弦的词不占和弦槽,连贯)。
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.end,
        spacing: 4,
        runSpacing: 2,
        children: children,
      ),
    );
  }
}

/// 一个词单元:
/// - 有和弦 → Column[和弦贴片, 词]。Column 宽 = max(贴片宽, 词宽),所以贴片比词宽时
///   (如 "I" 配 C),单元被撑宽 → 它和下一个词之间自动多出间隙,和弦不挤不叠。
/// - 无和弦 → 纯词(Wrap 底对齐,和有和弦的词同一基线)。
class _WordUnitView extends StatelessWidget {
  final String? chord;
  final String word;
  final bool isCurrent;

  const _WordUnitView({this.chord, required this.word, this.isCurrent = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (chord == null) {
      return Text(word, style: theme.textTheme.bodyLarge);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _ChordChip(chord!, isCurrent: isCurrent, compact: true),
        const SizedBox(height: 3),
        Text(word, style: theme.textTheme.bodyLarge),
      ],
    );
  }
}

/// 单个和弦贴片:圆角小色块 + 和弦名。
/// isCurrent 时反色(主色实底 + 反色字)把"现在按这个"点出来。
/// compact=true 用更小的字号/内边距,给"和弦浮在歌词上方"那种紧凑贴片用。
class _ChordChip extends StatelessWidget {
  final String chord;
  final bool isCurrent;
  final bool compact;

  const _ChordChip(this.chord, {this.isCurrent = false, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 10,
        vertical: compact ? 1 : 4,
      ),
      decoration: BoxDecoration(
        color: isCurrent ? cs.primary : cs.primaryContainer,
        borderRadius: BorderRadius.circular(compact ? 5 : 8),
        border: Border.all(color: cs.primary, width: 1),
      ),
      child: Text(
        chord,
        style: TextStyle(
          color: isCurrent ? cs.onPrimary : cs.onPrimaryContainer,
          fontWeight: FontWeight.bold,
          fontSize: compact ? 12 : 14,
        ),
      ),
    );
  }
}

/// 和弦指法图:4 弦 × 4 品的网格,标出每根弦按第几品(实心点)、哪些是空弦(空心圈)。
/// frets 按 G C E A 顺序,0 = 空弦。scale 放大显示(坐标系固定 56×80)。复刻 Web 版 drawChord。
class ChordDiagram extends StatelessWidget {
  final List<int> frets;
  final double scale;

  const ChordDiagram({required this.frets, this.scale = 1, super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 56 * scale,
      height: 80 * scale,
      child: CustomPaint(
        painter: _ChordPainter(frets: frets, scale: scale, cs: cs),
      ),
    );
  }
}

class _ChordPainter extends CustomPainter {
  final List<int> frets;
  final double scale;
  final ColorScheme cs;

  const _ChordPainter({
    required this.frets,
    required this.scale,
    required this.cs,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(scale); // 之后用 56×80 的固定坐标画,scale 负责放大显示
    const left = 10.0, right = 46.0, top = 16.0, bottom = 72.0;
    const nStrings = 4, nFrets = 4;
    final dx = (right - left) / (nStrings - 1); // 弦间距 = 12
    final dy = (bottom - top) / nFrets; // 品间距 = 14

    final grid = Paint()
      ..color = cs.outline
      ..strokeWidth = 1;
    final nut = Paint()
      ..color = cs.onSurface
      ..strokeWidth = 3;
    final open = Paint()
      ..color = cs.onSurfaceVariant
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final pressed = Paint()
      ..color = cs.primary
      ..style = PaintingStyle.fill;

    // (1) 空弦圈:fret 0 的弦,在琴枕上方画空心圆
    for (var i = 0; i < nStrings; i++) {
      if (frets[i] == 0) {
        canvas.drawCircle(Offset(left + i * dx, 8), 3, open);
      }
    }
    // (2) 琴枕(nut):顶部粗线
    canvas.drawLine(Offset(left, top), Offset(right, top), nut);
    // (3) 品丝:4 条横线
    for (var f = 1; f <= nFrets; f++) {
      final y = top + f * dy;
      canvas.drawLine(Offset(left, y), Offset(right, y), grid);
    }
    // (4) 弦:4 根竖线
    for (var i = 0; i < nStrings; i++) {
      final x = left + i * dx;
      canvas.drawLine(Offset(x, top), Offset(x, bottom), grid);
    }
    // (5) 按弦点:fret>0 的弦,在对应品格中点画实心圆
    for (var i = 0; i < nStrings; i++) {
      if (frets[i] > 0) {
        final x = left + i * dx;
        final y = top + (frets[i] - 0.5) * dy;
        canvas.drawCircle(Offset(x, y), 5, pressed);
      }
    }
  }

  @override
  bool shouldRepaint(_ChordPainter old) =>
      old.frets != frets || old.scale != scale;
}

/// 顶部练习栏(吸顶):现在弹哪个和弦(大指法图)+ 这一组扫到第几下(一排 ↓)+ 下一个和弦。
/// 数据全是父级算好传进来的;它自己没状态,只负责显示。对齐 Web 版 .panel。
class _PracticeBar extends StatelessWidget {
  final String chord; // 当前和弦名
  final int beat; // 当前第几拍(0 起)
  final int beatsPerChord; // 一组几拍
  final String nextChord; // 下一个和弦名
  final int tempo; // 当前速度(可调,实际在用的 BPM)
  final int minTempo; // 滑块最慢一档(约原速一半)
  final int maxTempo; // 滑块最快一档(原速)
  final ValueChanged<int> onTempoChanged; // 拖滑块时回调父级 _setTempo

  const _PracticeBar({
    required this.chord,
    required this.beat,
    required this.beatsPerChord,
    required this.nextChord,
    required this.tempo,
    required this.minTempo,
    required this.maxTempo,
    required this.onTempoChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Column(
        children: [
          Text(
            '现在弹 $chord',
            style: TextStyle(
              fontSize: 13,
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          // 大指法图:这和弦在 chordShapes 里有数据就画图;没有就退回显示字母(防以后加新和弦没数据)。
          chordShapes.containsKey(chord)
              ? ChordDiagram(frets: chordShapes[chord]!, scale: 1.3)
              : Text(
                  chord,
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    color: cs.primary,
                  ),
                ),
          const SizedBox(height: 6),
          // 扫弦点:一组几拍就画几个 ↓,当前那下用主色,其余暗淡。
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < beatsPerChord; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '↓',
                    style: TextStyle(
                      fontSize: 22,
                      color: i == beat ? cs.primary : cs.outline,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '第 ${beat + 1} / $beatsPerChord 拍  ·  下一个: $nextChord',
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          // 调速滑块:左"调速"字、中间滑块、右边实时 BPM。范围约 = 原速的一半 ~ 两倍。
          // clamp 是保险:万一 tempo 落在 [min,max] 外(理论上不会),Slider 会断言报错,钳一下就稳。
          Row(
            children: [
              Text(
                '调速',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              Expanded(
                child: Slider(
                  value: tempo.clamp(minTempo, maxTempo).toDouble(),
                  min: minTempo.toDouble(),
                  max: maxTempo.toDouble(),
                  divisions: maxTempo > minTempo ? maxTempo - minTempo : null,
                  label: '$tempo BPM',
                  onChanged: (v) => onTempoChanged(v.round()),
                ),
              ),
              SizedBox(
                width: 60,
                child: Text(
                  '$tempo BPM',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
