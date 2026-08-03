// 尤克里里弹唱练习 —— Flutter 版主入口 + 歌曲页。
//
// 这一版:歌曲页展示"歌词 + 和弦",顶栏下拉框选歌,练习栏调速行最左的 ▶ 按一下就按 BPM 嗒嗒响(节拍器)。
// 节拍器一边打拍、一边把"当前和弦"按拍数往前推进:顶部练习栏显示现在弹哪个、扫到第几下、下一个是什么;
// 歌词里当前和弦贴片反色点亮、当前行微微高亮并自动滚到屏幕中间。播到末尾循环回开头。
// 练习栏里:一排和弦卡 = 当前这一行的和弦,弹到哪个、那张就变大指法图高亮,其余小参考;卡跟当前行一一对应。
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
  // 当前是这一组和弦里的第几个【8分音符槽位】(0 = 第1拍正拍 = 要播重音;1 = 第1拍的"&"……)。
  // 一组共 beatsPerChord×2 个槽。用半拍粒度定时,是为了让"上扫↑"这种落在拍间的扫弦(海岛节奏)能逐下高亮。
  // 第几拍 = _slot ~/ 2;偶数槽 = 正拍(响节拍器)、奇数槽 = 后半拍(不响,留给上扫)。
  int _slot = 0;
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
  // 每一行歌词的和弦(按出现顺序、含重复),按"全局行下标"取。给练习栏那一排卡用——
  // 那一排只显示【当前这一行】用到的和弦,跟正在唱的词一一对应,不掺别的行的和弦。
  List<List<String>> _lineChords = [];
  // 每一行第 1 个和弦在 _flat 里的起始下标。用来把全局 _idx 折算成"当前行内的第几个和弦"。
  List<int> _lineStartFlat = [];
  // 每一行歌词一个 GlobalKey,自动滚动时靠它定位"滚到这一行"。
  List<GlobalKey> _lineKeys = [];
  // 上一次高亮的是第几行;变了才滚动,避免每拍都抖一下。
  int _lastLine = 0;
  // 已完整练了几遍:引擎从末尾循环回开头一次就 +1。给练习一点"打了多少卡"的反馈。
  int _loops = 0;

  // —— 预备拍(倒计时)——
  // _inCountIn:正在数预备拍吗。从头第一次按 ▶ 时置 true,数完一小节(beatsPerChord×2 个槽)置 false。
  // _everPlayed:这首歌这一轮"正式开始播"过了吗。只在"从头第一次按 ▶"给一轮预备拍;
  // 暂停后恢复、以及自动循环回开头都不重复数——预备拍是给"人"准备手用的,机器自己循环不需要。
  bool _inCountIn = false;
  bool _everPlayed = false;

  // —— 扫弦节奏型 ——
  // 当前选的第几个节奏型(patternsFor 返回的那几个)。换歌不重置——节奏型是练习偏好,跨歌保留。
  int _patternIndex = 0;

  // —— 分段 AB 循环 ——
  // _markerA / _markerB:用户在歌词上点的两个"循环点"(行下标)。两个都标好 → 引擎到 B 行末尾跳回 A 行开头反复。
  // 只标了 A(_markerB 仍 null)= 还没成区间,只在那一行显示 A 徽标。换歌清空(行下标是按某首歌的行算的,不能跨歌保留)。
  int? _markerA;
  int? _markerB;

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

  /// 把当前选中的歌拍扁成练习用的数组:_flat / _lineOfChord / _lineKeys,
  /// 外加"每行的和弦 + 每行在 _flat 的起点"(给练习栏按"当前行"画那一排卡用)。
  /// 对齐 Web 版 buildSong() 里的 flat / lineOfChord 逻辑(逐行、按出现顺序)。
  void _rebuildFlat() {
    final song = songs[_selected];
    _flat = [];
    _lineOfChord = [];
    final keys = <GlobalKey>[];
    _lineChords = [];
    _lineStartFlat = [];
    var lineIdx = 0;
    for (final section in song.sections) {
      for (final line in section.lines) {
        keys.add(GlobalKey()); // 每行一个 key,自动滚动定位用
        _lineChords.add(line.chords); // 这行的和弦(顺序、含重复)
        _lineStartFlat.add(_flat.length); // 这行第 1 个和弦在 _flat 里的位置
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

  /// 两个【8分音符槽位】之间的间隔(= 半拍)。BPM = 每分钟多少拍,一拍 = 60000/BPM 毫秒,半拍再 ÷2。
  /// 例:72 BPM → 一拍 ≈ 833 毫秒,半拍 ≈ 417 毫秒。读 _tempo(可调),不读 song.tempo(原速)。
  /// 用半拍粒度定时,是为了让"上扫"这种落在拍间的扫弦(海岛节奏)也能逐下高亮、跟得上。
  Duration get _halfBeat =>
      Duration(milliseconds: (30000 / _tempo).round());

  // —— AB 循环的只读折算(仅在 _abActive 时调用才合法)——
  bool get _abActive => _markerA != null && _markerB != null;
  // A、B 谁先点不一定(可能先点后面的行),取小当起点、大当终点。
  int get _loopStartLine => _markerA! <= _markerB! ? _markerA! : _markerB!;
  int get _loopEndLine => _markerA! >= _markerB! ? _markerA! : _markerB!;
  // AB 区间在 _flat 里的和弦范围:从起点行第 1 个和弦,到终点行最后一个和弦。
  int get _loopFirstChord => _lineStartFlat[_loopStartLine];
  int get _loopLastChord =>
      _lineStartFlat[_loopEndLine] + _lineChords[_loopEndLine].length - 1;

  /// 点一行歌词:设 A,再点一行设 B(成区间、立刻把位置拉到 A 开头好让循环起跑);
  /// 两个都标过后再点 = 重新开始(把这次点的当新 A)。给 _LineView 的 onTap 用。
  void _onLineTapped(int lineIdx) {
    setState(() {
      if (_markerA == null) {
        _markerA = lineIdx;
      } else if (_markerB == null) {
        _markerB = lineIdx;
        // 两点成区间 → 立刻跳到起点行第 1 个和弦、槽归 0,循环马上从 A 起跑。
        _idx = _lineStartFlat[_loopStartLine];
        _slot = 0;
        _lastLine = (_lineOfChord.isNotEmpty && _idx < _lineOfChord.length)
            ? _lineOfChord[_idx]
            : _lastLine;
      } else {
        // 都标过了 → 重新开始:这次点的当新 A,清掉 B。
        _markerA = lineIdx;
        _markerB = null;
      }
    });
  }

  /// 清除 AB 区间,回到整曲循环。位置不动,让它自然走到下一处。
  void _clearAb() {
    setState(() {
      _markerA = null;
      _markerB = null;
    });
  }

  /// 某一行该显示什么 AB 标记:none / a / b。给 _LineView 画徽标用。
  _AbMarker _markerForLine(int l) {
    if (_markerA == l && _markerB == null) return _AbMarker.a; // 只标了 A
    if (_abActive) {
      if (l == _loopStartLine) return _AbMarker.a;
      if (l == _loopEndLine) return _AbMarker.b;
    }
    return _AbMarker.none;
  }

  /// 按一下 ▶/⏸:正在响就停,没响就接着弹。
  /// 对齐 Web:不归零、resume——暂停后再按 ▶ 接着上次停的地方继续;只有换歌才从头(见 _onSongChanged)。
  void _togglePlay() {
    if (_playing) {
      _timer?.cancel();
      _timer = null;
    } else {
      // 从头第一次按 ▶:先数一小节预备拍(beatsPerChord 拍"1-2-3-4"),给新手把手指放好的时间。
      // 已经正式开始过(暂停后恢复)就不重复数。预备拍借用 _slot 走一小节,数完进正式播放。
      if (!_everPlayed) {
        _inCountIn = true;
        _slot = 0; // 预备拍从槽0(第1拍)开始
        // 设了 AB 区间的话,"从头开始" = 从 A 行开头开始(而不是歌曲第1和弦),好让练习聚焦在指定段。
        if (_abActive) {
          _idx = _loopFirstChord;
          _lastLine = (_lineOfChord.isNotEmpty && _idx < _lineOfChord.length)
              ? _lineOfChord[_idx]
              : _lastLine;
        }
      }
      // 立刻响当下这一下(预备拍第1下 或 恢复处的槽),不用干等半拍。
      _tick();
      _startTimer();
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
      _slot = 0;
      _loops = 0; // 换歌重新计数
      _inCountIn = false; // 换歌取消可能进行中的预备拍
      _everPlayed = false; // 新歌从头算"还没正式开始",下次按 ▶ 会重新数预备拍
      _markerA = null; // 换歌清空 AB(行下标按某首歌的行算,不能跨歌保留)
      _markerB = null;
      _tempo = songs[i].tempo; // 新歌用新歌的原速,免得还按上一首调出来的慢速走
      _rebuildFlat();
      _lastLine = _lineOfChord.isNotEmpty ? _lineOfChord[0] : 0;
    });
  }

  /// 拖滑块调速。正在播放时,旧 Timer.periodic 的间隔是【创建那一刻】就定死的、改 _tempo 它不知道,
  /// 所以必须 cancel 掉、用新的 _halfBeat 再起一个(下一个槽就按新速度来)。
  /// 不归零位置(_idx/_slot 不动)、也不立刻补响一声——否则会跟刚才那下叠在一起。
  /// 暂停时调也没事:只更新 _tempo,下次按 ▶ 自然用新速度。
  void _setTempo(int v) {
    if (v == _tempo) return;
    setState(() => _tempo = v);
    if (_playing) {
      _timer?.cancel();
      _startTimer();
    }
  }

  /// 起/重启半拍定时器:每个槽(8分音符)推进一下 + 响 + 刷新。按▶、调速都走它,推进逻辑只此一份。
  void _startTimer() {
    _timer = Timer.periodic(_halfBeat, (_) => _onTimerTick());
  }

  /// 定时器每一下(一个8分音符槽):先推进位置,再 _tick 响+刷新。推进放前面,重画读到的才是"正在响"那下。
  /// 预备拍期间:_slot 走满一小节 = 预备拍结束 → 进正式播放。
  /// 正式播放:一小节(= 一个和弦)走完 → 进下一个和弦,末尾循环回开头。
  void _onTimerTick() {
    final slotsPerBar = songs[_selected].beatsPerChord * 2;
    _slot++;
    if (_slot >= slotsPerBar) {
      _slot = 0;
      if (_inCountIn) {
        // 预备拍数完一小节 → 正式开始(_idx 本就是 0,从第一和弦第一拍开始)
        _inCountIn = false;
        _everPlayed = true;
      } else if (_flat.isNotEmpty) {
        // AB 循环优先:到 B 行末尾就跳回 A 行开头(单独计一遍);否则正常推进 / 整曲末尾循环回开头。
        if (_abActive && _idx >= _loopLastChord) {
          _idx = _loopFirstChord;
          _loops++;
        } else if (_idx + 1 >= _flat.length) {
          _idx = 0;
          _loops++;
        } else {
          _idx++;
        }
      }
    }
    _tick();
  }

  /// 走一下:该响就响 + 刷新界面。这里【不】改 _slot/_idx/_inCountIn —— 推进放 _onTimerTick 里、在"下一槽"之前做。
  /// 因为 setState 延迟到下一帧才重画:若这边 setState 完就改值,重画读到的会是改后的值,扫弦会比声音快半拍(踩过的坑)。
  /// 节拍器只在【正拍】(偶数槽)响:槽0 重音(第1拍)、槽 2/4/6 普通嗒;后半拍(奇数槽)不响——那是给"上扫"留的空,节拍器不抢。
  /// 预备拍期间:同样的正拍响法(_slot 走的是预备那一小节),位置不动、不滚动。
  void _tick() {
    if (_slot.isEven) {
      _playClick(accent: _slot == 0); // 槽0 = 第1拍 = 重音(预备拍的"1"和正式第1拍都是)
    }
    setState(() {}); // 刷新:练习栏(倒计时数字 / 扫弦型)、和弦贴片、当前行高亮
    if (!_inCountIn) _maybeScrollToCurrentLine();
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
    final cs = theme.colorScheme;
    // 进度条:整曲模式按整首歌走;AB 模式只走 AB 区间那一段(到 B 回 0)。空歌算 0。
    final double progress;
    if (_flat.isEmpty) {
      progress = 0.0;
    } else if (_abActive) {
      final span = _loopLastChord - _loopFirstChord + 1;
      progress =
          ((_idx - _loopFirstChord) + _slot / (song.beatsPerChord * 2)) / span;
    } else {
      progress = (_idx + _slot / (song.beatsPerChord * 2)) / _flat.length;
    }

    // 预备拍当前数到第几拍(1..beatsPerChord);0 = 不在数预备拍。
    // _slot 走一小节:槽 0/1→第1拍、2/3→第2拍 …… 偶数槽=刚敲到这拍、奇数槽=这拍的"&(数字不变)。
    final countInNumber = _inCountIn ? _slot ~/ 2 + 1 : 0;

    // 当前节奏型 + 它拍成的"按槽位取方向"网格(长度 = beatsPerChord×2)。给练习栏逐槽高亮、画 ↓/↑ 用。
    final patterns = patternsFor(song.beatsPerChord);
    final pattern = patterns[_patternIndex.clamp(0, patterns.length - 1)];
    final strumGrid = pattern.grid(song.beatsPerChord);

    // 把"段落标题 + 每一行"拍平成列表,同时数出每个和弦/每行的全局下标,
    // 用来标记"当前该高亮哪个和弦贴片、哪行歌词"。
    final List<Widget> items = [];
    final currentLine = (_flat.isEmpty || _idx >= _lineOfChord.length)
        ? 0
        : _lineOfChord[_idx];
    // 练习栏那一排卡 =【当前这一行】的和弦(顺序、含重复);当前弹到行内第几个由 _idx 折算。
    // 这样那一排永远跟正在唱的词一一对应,不会掺入别行的和弦(如 Let It Be 唱到 C G F C 那行就不该有 Am)。
    final lineChords = currentLine < _lineChords.length
        ? _lineChords[currentLine]
        : <String>[];
    final currentChordIndex = currentLine < _lineStartFlat.length
        ? _idx - _lineStartFlat[currentLine]
        : 0;
    var chordCursor = 0; // 走到第几个和弦(全局)
    var lineCursor = 0; // 走到第几行(全局)
    for (final section in song.sections) {
      if (section.name != null) {
        items.add(_SectionHeader(section.name!));
      }
      for (final line in section.lines) {
        final marker = _markerForLine(lineCursor);
        final inRange = _abActive &&
            lineCursor >= _loopStartLine &&
            lineCursor <= _loopEndLine;
        items.add(
          _LineView(
            line: line,
            lineKey: _lineKeys[lineCursor],
            isCurrentLine: lineCursor == currentLine,
            chordStart: chordCursor, // 这一行第 1 个和弦的全局下标
            currentChord: _idx,
            marker: marker,
            inRange: inRange,
            onTap: () => _onLineTapped(lineCursor),
          ),
        );
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
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
          icon: Icon(Icons.arrow_drop_down, color: theme.colorScheme.onSurface),
        ),
        // 第二行:速度信息。用 AppBar 的 bottom 槽放,跟标题各占一行,互不重叠。
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '$_tempo BPM${_tempo == song.tempo ? '' : (_tempo < song.tempo ? ' · 慢练' : ' · 加速')} · ${song.beatsPerChord}拍 · 第1拍重音${_loops > 0 ? ' · 已练 $_loops 遍' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // 顶部练习栏(吸顶):一排和弦卡 =【当前这一行】的和弦(弹到哪个、那张变大图高亮,其余小参考)+
          // 这一组扫到第几下(一排 ↓)+ 下一个和弦 + 调速滑块。卡跟当前行一一对应,不掺别行的和弦。
          _PracticeBar(
            lineChords: lineChords,
            currentChordIndex: currentChordIndex,
            slot: _slot,
            beatsPerChord: song.beatsPerChord,
            strumGrid: strumGrid,
            patternNames: [for (final p in patterns) p.name],
            patternIndex: _patternIndex,
            onPatternChanged: (i) => setState(() => _patternIndex = i),
            abActive: _abActive,
            onClearAb: _clearAb,
            countInNumber: countInNumber,
            nextChord: _flat.isEmpty
                ? '—'
                : (_abActive && _idx >= _loopLastChord
                    ? _flat[_loopFirstChord] // AB 到 B 末尾:下一个就是跳回 A 的那个和弦
                    : _flat[(_idx + 1) % _flat.length]),
            tempo: _tempo,
            minTempo: (song.tempo / 2).round(), // 最慢到原速一半
            maxTempo: (song.tempo * 2).round(), // 最快到原速两倍——放开加速练
            onTempoChanged: _setTempo,
            isPlaying: _playing,
            canPlay: _ready,
            onTogglePlay: _togglePlay,
          ),
          // 整首进度条:细一条,贴在歌词区顶上。走完一遍循环时回 0。一眼知道还剩多少。
          LinearProgressIndicator(
            value: progress,
            minHeight: 3,
            backgroundColor: cs.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
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
      // ▶/⏸ 已挪进练习栏的调速行(最左小图标),不再用右下大圆按钮——它会在歌长时挡住歌词。
    );
  }
}

/// AB 循环点的标记类型:不是标记 / A 点(起点)/ B 点(终点)。
enum _AbMarker { none, a, b }

/// AB 循环点的行徽标:一个小圆,写着 A 或 B。点在歌词行左边标出区间起止。
class _AbBadge extends StatelessWidget {
  final _AbMarker marker;
  const _AbBadge(this.marker);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.primary,
        shape: BoxShape.circle,
      ),
      child: Text(
        marker == _AbMarker.a ? 'A' : 'B',
        style: TextStyle(
          color: cs.onPrimary,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
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
  final _AbMarker marker; // 这行的 AB 标记(none/a/b)
  final bool inRange; // 这行在 AB 区间内吗(区间内的行加左边框、淡底色)
  final VoidCallback? onTap; // 点这行 → 设 AB 循环点

  const _LineView({
    required this.line,
    required this.lineKey,
    required this.isCurrentLine,
    required this.chordStart,
    required this.currentChord,
    this.marker = _AbMarker.none,
    this.inRange = false,
    this.onTap,
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        key: lineKey,
        padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
        decoration: BoxDecoration(
          color: isCurrentLine
              ? cs.primaryContainer.withValues(alpha: 0.3)
              : (inRange ? cs.primaryContainer.withValues(alpha: 0.12) : null),
          borderRadius: BorderRadius.circular(6),
          border: Border(
            left: BorderSide(
              color: inRange ? cs.primary : Colors.transparent,
              width: inRange ? 3 : 0,
            ),
          ),
        ),
        // 左边可能一个 AB 徽标,右边是歌词词单元(Wrap)。徽标顶对齐,词按基线排。
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (marker != _AbMarker.none)
              Padding(
                padding: const EdgeInsets.only(top: 3, right: 6),
                child: _AbBadge(marker),
              ),
            Expanded(
              // Wrap:词单元横向排开、窄屏自动换行。crossAxisAlignment=end → 所有词同基线,
              // 和弦只浮在"有和弦的词"上方(没和弦的词不占和弦槽,连贯)。
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: 4,
                runSpacing: 2,
                children: children,
              ),
            ),
          ],
        ),
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

/// 顶部练习栏(吸顶):一排和弦卡 =【当前这一行】的和弦,弹到哪个、那张就变大指法图并高亮,其余当小参考。
/// 下面:这一组扫到第几下(一排 ↓)+ 下一个和弦 + 调速滑块。
/// 数据全是父级算好传进来的;它自己没状态,只负责显示。对齐 Web 版 .panel。
class _PracticeBar extends StatelessWidget {
  final List<String> lineChords; // 当前这一行的和弦(顺序、含重复)
  final int currentChordIndex; // 当前弹到这一行的第几个(0 起)
  final int slot; // 当前8分音符槽位(0 起,一组共 beatsPerChord×2 个)
  final int beatsPerChord; // 一组几拍
  final List<StrumDir> strumGrid; // 当前节奏型按槽位拍成的方向网格(长度 = beatsPerChord×2)
  final List<String> patternNames; // 可选节奏型的名字(给那一排选择芯片用)
  final int patternIndex; // 当前选第几个节奏型
  final ValueChanged<int> onPatternChanged; // 切节奏型时回调父级
  final bool abActive; // AB 循环区间设好了吗(没设就显示提示,设了显示状态 + ✕)
  final VoidCallback onClearAb; // 清除 AB 区间
  final int countInNumber; // 预备拍当前数到几(1..beatsPerChord);0 = 不在数预备拍
  final String nextChord; // 下一个和弦名
  final int tempo; // 当前速度(可调,实际在用的 BPM)
  final int minTempo; // 滑块最慢一档(约原速一半)
  final int maxTempo; // 滑块最快一档(原速)
  final ValueChanged<int> onTempoChanged; // 拖滑块时回调父级 _setTempo
  final bool isPlaying; // 现在在打拍吗(决定显示 ⏸ 还是 ▶)
  final bool canPlay; // 音频加载好了吗(没好就灰掉、按不动)
  final VoidCallback onTogglePlay; // 按一下 ▶/⏸

  const _PracticeBar({
    required this.lineChords,
    required this.currentChordIndex,
    required this.slot,
    required this.beatsPerChord,
    required this.strumGrid,
    required this.patternNames,
    required this.patternIndex,
    required this.onPatternChanged,
    required this.abActive,
    required this.onClearAb,
    required this.countInNumber,
    required this.nextChord,
    required this.tempo,
    required this.minTempo,
    required this.maxTempo,
    required this.onTempoChanged,
    required this.isPlaying,
    required this.canPlay,
    required this.onTogglePlay,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // 这一行的和弦卡:按行内顺序排,弹到第几个(currentChordIndex)那张就变大图高亮,其余小参考。
    // 第 1 张前面不留间距,之后每张前面塞 8px 间隙(Row 没有 spacing 参数,这是常见写法)。
    final refCards = <Widget>[];
    for (var i = 0; i < lineChords.length; i++) {
      if (i > 0) refCards.add(const SizedBox(width: 8));
      refCards.add(
        _ChordRefCard(name: lineChords[i], isCurrent: i == currentChordIndex),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Column(
        children: [
          // 一排和弦卡:这首歌所有和弦各一张,弹到哪个、那张就自动变大图并高亮,其余当小参考。
          // 不再单独画大图——"现在弹哪个"由这一排里被放大的那张直接表达。横向可滚,和弦多也不撑爆。
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: refCards,
            ),
          ),
          const SizedBox(height: 6),
          // 节奏型选择:一排小芯片,点哪个用哪个。预备拍时也能选(提前挑好)。
          Wrap(
            spacing: 6,
            children: [
              for (var i = 0; i < patternNames.length; i++)
                ChoiceChip(
                  label: Text(
                    patternNames[i],
                    style: const TextStyle(fontSize: 12),
                  ),
                  selected: i == patternIndex,
                  onSelected: (_) => onPatternChanged(i),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          // AB 循环状态行:没设时给操作提示;设好后显示"循环中"+ ✕ 清除。
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: abActive
                ? Row(
                    children: [
                      Icon(Icons.repeat_rounded, size: 16, color: cs.primary),
                      const SizedBox(width: 4),
                      Text(
                        'AB 循环中',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: onClearAb,
                        tooltip: '清除 AB 区间',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        icon: const Icon(Icons.close_rounded, size: 18),
                        style: IconButton.styleFrom(
                          foregroundColor: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  )
                : Text(
                    '👆 点两行歌词设 AB 循环点(到 B 跳回 A 反复练)',
                    style: TextStyle(fontSize: 11, color: cs.outline),
                  ),
          ),
          const SizedBox(height: 4),
          // 扫弦型 / 预备拍数字(二选一):
          // 正式播放:按8分音符槽位画一排 ↓/↑/(·休止),当前槽高亮放大;正拍(偶数槽)前留宽缝,把"一拍两槽"归成一组,节奏一眼可读。
          // 预备拍(countInNumber>0):换成大字 1..N 倒计时,当前那拍高亮(跟旧版一致)。
          countInNumber > 0
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < beatsPerChord; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: i + 1 == countInNumber ? 28 : 18,
                            fontWeight: FontWeight.bold,
                            color: i + 1 == countInNumber
                                ? cs.primary
                                : cs.outline,
                          ),
                        ),
                      ),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < strumGrid.length; i++) ...[
                      if (i > 0) SizedBox(width: i.isEven ? 14 : 6),
                      if (strumGrid[i] == StrumDir.rest)
                        Text(
                          '·',
                          style: TextStyle(
                            fontSize: 14,
                            color: cs.outline.withValues(alpha: 0.4),
                          ),
                        )
                      else
                        Text(
                          strumGrid[i] == StrumDir.down ? '↓' : '↑',
                          style: TextStyle(
                            fontSize: i == slot ? 24 : 18,
                            fontWeight: FontWeight.bold,
                            color: i == slot ? cs.primary : cs.outline,
                          ),
                        ),
                    ],
                  ],
                ),
          const SizedBox(height: 4),
          // 信息行:预备拍时提示"准备从哪个和弦开始";否则显示当前第几拍 + 下一个和弦。
          Text(
            countInNumber > 0
                ? '预备拍 · 准备从「${lineChords.isNotEmpty ? lineChords.first : '—'}」开始'
                : '第 ${slot ~/ 2 + 1} / $beatsPerChord 拍  ·  下一个: $nextChord',
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          // 调速行:最左 ▶/⏸ 小图标(节拍器总开关)+ "调速"字 + 中间滑块 + 右边实时 BPM。
          // ▶/⏸ 从右下大圆按钮挪到这里当小图标,免得歌长时挡住歌词。
          // clamp 是保险:万一 tempo 落在 [min,max] 外(理论上不会),Slider 会断言报错,钳一下就稳。
          Row(
            children: [
              IconButton(
                onPressed: canPlay ? onTogglePlay : null,
                tooltip: isPlaying ? '暂停' : '开始打拍',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
                style: IconButton.styleFrom(
                  foregroundColor: cs.primary,
                  disabledForegroundColor: cs.onSurfaceVariant.withValues(
                    alpha: 0.4,
                  ),
                ),
              ),
              const SizedBox(width: 4),
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

/// 练习栏那一排里的和弦卡:和弦名(上)+ 指法图(下)。
/// isCurrent(现在弹的这个)时:指法图放大、字号变大 + 主色高亮边框/底色——一排里被放大的那张就是"现在弹哪个"。
/// 其余和弦用小一号指法图当参考。和弦在 chordShapes 里有数据就画图;没有(以后加了没录指法的)退回不崩。
class _ChordRefCard extends StatelessWidget {
  static const _currentScale = 1.0; // 当前和弦的大图
  static const _otherScale = 0.65; // 其余参考和弦的小图

  final String name;
  final bool isCurrent;

  const _ChordRefCard({required this.name, this.isCurrent = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final scale = isCurrent ? _currentScale : _otherScale;
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
      decoration: BoxDecoration(
        color: isCurrent
            ? cs.primaryContainer.withValues(alpha: 0.55)
            : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isCurrent ? cs.primary : cs.outlineVariant,
          width: isCurrent ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            style: TextStyle(
              fontSize: isCurrent ? 15 : 12,
              fontWeight: FontWeight.bold,
              color: cs.primary,
            ),
          ),
          // 有指法数据就画图(当前和弦用大图、其余小图);没数据时:当前和弦退回大字母、其余占位保高。
          chordShapes.containsKey(name)
              ? ChordDiagram(frets: chordShapes[name]!, scale: scale)
              : isCurrent
              ? Text(
                  name,
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: cs.primary,
                  ),
                )
              : const SizedBox(height: 52),
        ],
      ),
    );
  }
}
