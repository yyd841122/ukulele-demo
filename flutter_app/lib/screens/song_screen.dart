// 歌曲页:顶栏下拉选歌,正文铺出当前歌的每一段、每一行;节拍器一边打拍、一边推进"当前和弦"。
// 从 main.dart 拆出(第19步重构)。这里只放 SongScreen + 它的状态;界面部件在 widgets/,音频在 audio/。
//
// 这一版:歌曲页展示"歌词 + 和弦",顶栏下拉框选歌,练习栏调速行最左的 ▶ 按一下就按 BPM 嗒嗒响(节拍器)。
// 节拍器一边打拍、一边把"当前和弦"按拍数往前推进:顶部练习栏显示现在弹哪个、扫到第几下、下一个是什么;
// 歌词里当前和弦贴片反色点亮、当前行微微高亮并自动滚到屏幕中间。播到末尾循环回开头。
// 练习栏里:一排和弦卡 = 当前这一行的和弦,弹到哪个、那张就变大指法图高亮,其余小参考;卡跟当前行一一对应。
import 'dart:async'; // Timer(定时器)在这

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../audio/audio_engine.dart';
import '../models.dart';
import '../prefs/app_preferences.dart';
import '../widgets/lyric_view.dart';
import '../widgets/practice_bar.dart';

/// 歌曲页:顶栏下拉选歌,正文铺出当前歌的每一段、每一行。
/// 因为要"记住当前选的是哪首"+ 节拍器状态,这里用 StatefulWidget(带状态)。
///
/// audio 由外层 MainScaffold 注入并拥有(第28步:多个 tab 共用一份引擎,不在本页自建/自释放)。
class SongScreen extends StatefulWidget {
  final AudioEngine audio;

  const SongScreen({required this.audio, super.key});

  @override
  State<SongScreen> createState() => SongScreenState();
}

/// public:MainScaffold 持 `GlobalKey<SongScreenState>`,切走练习 tab 时调 flushStats()
/// 把当前会话打卡刷盘,这样平级的统计 tab 才读得到含本次练习的最新值。
class SongScreenState extends State<SongScreen> {
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
  // 节奏型试听用的独立一次性定时器(跟主节拍器 _timer 互不干扰)。点节奏型芯片时起、走完一小节自停。
  Timer? _previewTimer;
  int _previewSlot = 0;
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

  // —— 练琴打卡(累计、持久化,跨会话)——
  // _totalLoops:【当前这首歌】累计完整练了多少遍(本次会话的 _loops 换歌清零,这个跨重启保留)。
  // _totalSec:【当前这首歌】累计练了多少秒(只在播放中计时)。
  int _totalLoops = 0;
  int _totalSec = 0;
  // 正在播放时记下开始时刻;暂停/换歌/销毁时把它结成秒数加进 _totalSec(见 _accumulateSec)。
  DateTime? _playStart;

  // —— 预备拍(倒计时)——
  // _inCountIn:正在数预备拍吗。从头第一次按 ▶ 时置 true,数完一小节(beatsPerChord×2 个槽)置 false。
  // _everPlayed:这首歌这一轮"正式开始播"过了吗。只在"从头第一次按 ▶"给一轮预备拍;
  // 暂停后恢复、以及自动循环回开头都不重复数——预备拍是给"人"准备手用的,机器自己循环不需要。
  bool _inCountIn = false;
  bool _everPlayed = false;

  // —— 扫弦节奏型 ——
  // 当前选的第几个节奏型(patternsFor 返回的那几个)。换歌不重置——节奏型是练习偏好,跨歌保留。
  int _patternIndex = 0;

  // 扫弦声开关:开 = 播放时按节奏型播真扫弦声(代替嗒声);关 = 只敲节拍器嗒声。跨歌保留。
  bool _strumSoundOn = true;

  // 自动提速开关:开 = 每过一遍(整曲到尾 / AB 到 B)+3 BPM、到原速停(渐进提速练法)。跨歌保留。
  bool _rampOn = false;

  // 歌词字号缩放(1.0 = 默认;界面 Slider 限定 0.8~1.8)。全局偏好——跟哪首歌无关。
  double _lyricScale = 1.0;

  // —— 分段 AB 循环 ——
  // _markerA / _markerB:用户在歌词上点的两个"循环点"(行下标)。两个都标好 → 引擎到 B 行末尾跳回 A 行开头反复。
  // 只标了 A(_markerB 仍 null)= 还没成区间,只在那一行显示 A 徽标。换歌清空(行下标是按某首歌的行算的,不能跨歌保留)。
  int? _markerA;
  int? _markerB;

  // 持久化:记住上次的歌 / 速度 / 节奏型 / AB 区间。initState 里异步加载(_loadPrefs),
  // 没加载好之前是 null —— 各保存点都用 ?. 守住,加载好才真写。
  AppPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _rebuildFlat(); // 先把当前歌拍扁,界面第一次画就能显示"现在弹 第1个和弦"
    _tempo = songs[_selected].tempo; // 默认原速(late 字段必须在第一次被读之前赋上值)
    // 音频引擎由 MainScaffold 在 app 启动时统一 init(本页只调它的方法),这里不再 _initAudio。
    _loadPrefs(); // 异步读上次的歌/速度/节奏型/AB,读好再 reconcile(不卡首帧:首帧先用默认值画)
  }

  /// 异步读持久化偏好,读好把状态 reconcile 到上次的值(上次的歌、那首歌的速度、节奏型、AB)。
  /// 不阻塞首帧:首帧用默认值(歌0 / 原速)先画,这里读完再 setState 切过去。
  /// 测试环境 SharedPreferences 是自动 mock 的空库 → 读出来都是默认值,reconcile 等于没动。
  Future<void> _loadPrefs() async {
    final p = await AppPreferences.load();
    if (!mounted) return;
    setState(() {
      _prefs = p;
      _selected = p.getSongIndex(_selected).clamp(0, songs.length - 1);
      // clamp 防万一存了个越界值(节奏型以后还会加);上界按当前歌的节奏型数量动态取,别写死成数字。
      _patternIndex = p
          .getPatternIndex(_patternIndex)
          .clamp(0, patternsFor(songs[_selected].beatsPerChord).length - 1);
      _strumSoundOn = p.getStrumSound(true);
      _rampOn = p.getRamp();
      _lyricScale = p.getLyricScale(1.0).clamp(0.8, 1.8); // Slider 区间,防存了个越界值
      _rebuildFlat(); // 按载入的歌重新拍扁(歌曲可能从 0 变成上次的下标)
      _tempo = p.getTempo(songs[_selected].id) ?? songs[_selected].tempo;
      _totalLoops = p.getLoops(songs[_selected].id); // 上次这首歌累计练的遍数
      _totalSec = p.getSec(songs[_selected].id); // 上次这首歌累计练的秒数
      _lastLine = _lineOfChord.isNotEmpty ? _lineOfChord[0] : 0;
      // AB 是按歌存的行下标:万一 songs 改过、行数变了,越界的丢弃(否则后面 _loopStartLine 会越界)。
      final ab = p.getAb(songs[_selected].id);
      _markerA = _validLine(ab?.a);
      _markerB = _validLine(ab?.b);
    });
  }

  /// 校验一个载入的 AB 行下标是否还在当前歌的合法行范围内;不在就返回 null(丢弃)。
  int? _validLine(int? l) {
    if (l == null) return null;
    final total = _lineKeys.length; // 当前歌总行数
    return (l >= 0 && l < total) ? l : null;
  }

  /// 把当前 AB 区间写回持久化(成对存/清)。只在区间【成段】(两点都设好)或【清除】时存;
  /// A-only(刚开始标、还没成段)不存——重启不该恢复个半成品。
  void _saveAb() {
    final p = _prefs;
    if (p == null) return;
    if (_abActive) {
      p.setAb(songs[_selected].id, _markerA, _markerB);
    } else {
      p.setAb(songs[_selected].id, null, null);
    }
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

  @override
  void dispose() {
    // 页面销毁前最后存一次当前歌的速度(滑块拖动时不存、怕写太勤;走这里兜底)。
    _accumulateSec(); // 把正在播放的尾段时间结进 _totalSec(没在播就是 no-op)
    _prefs?.setTempo(songs[_selected].id, _tempo);
    _saveStats(); // 兜底存累计遍数 + 秒数
    _setWakelock(false); // 离开页面:释放屏幕常亮,别一直亮着耗电
    // 页面销毁时收尾:停闹钟、释放预览定时器。_audio 不在这释放——它归 MainScaffold 拥有。
    _timer?.cancel();
    _previewTimer?.cancel();
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
  /// 两个都标过后再点 = 重新开始(把这次点的当新 A)。给 LineView 的 onTap 用。
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
    _saveAb(); // 区间变了就存(成段存、半成品/清除就清掉)
  }

  /// 清除 AB 区间,回到整曲循环。位置不动,让它自然走到下一处。
  void _clearAb() {
    setState(() {
      _markerA = null;
      _markerB = null;
    });
    _saveAb(); // 清掉了,把存的也清掉
  }

  /// 某一行该显示什么 AB 标记:none / a / b。给 LineView 画徽标用。
  AbMarker _markerForLine(int l) {
    if (_markerA == l && _markerB == null) return AbMarker.a; // 只标了 A
    if (_abActive) {
      if (l == _loopStartLine) return AbMarker.a;
      if (l == _loopEndLine) return AbMarker.b;
    }
    return AbMarker.none;
  }

  /// 屏幕(键盘)常亮开关:练琴(播放)时开,暂停/换歌/退出时关。
  /// 包 try/catch:wakelock_plus 走平台通道,无头测试等环境没接好时 toggle 会抛
  /// MissingPluginException——不能让它崩界面(测试里 _onSongChanged 也会走到这)。
  Future<void> _setWakelock(bool on) async {
    try {
      await WakelockPlus.toggle(enable: on);
    } catch (e) {
      debugPrint('屏幕常亮切换失败: $e');
    }
  }

  /// 按一下 ▶/⏸:正在响就停,没响就接着弹。
  /// 对齐 Web:不归零、resume——暂停后再按 ▶ 接着上次停的地方继续;只有换歌才从头(见 _onSongChanged)。
  void _togglePlay() {
    if (_playing) {
      _timer?.cancel();
      _timer = null;
      _accumulateSec(); // 暂停:把这段播放时间结进 _totalSec
      _saveStats(); // 暂停时存一次累计(遍数 + 秒数),免得退出丢失
    } else {
      // 正式播放开始:打断可能正在放的节奏型试听,免得两串扫弦叠着响。
      _previewTimer?.cancel();
      _previewTimer = null;
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
      _playStart = DateTime.now(); // 记下开始播放的时刻(计时用)
      // 立刻响当下这一下(预备拍第1下 或 恢复处的槽),不用干等半拍。
      _tick();
      _startTimer();
    }
    _setWakelock(!_playing); // 要播就屏幕常亮、要停就恢复正常(_playing 还没翻,!它 = 新状态)
    setState(() => _playing = !_playing);
  }

  /// 换歌:速度可能变了,先停掉节拍器、把位置归零,再按新歌拍扁数据,免得还按上一首的旧结构走。
  void _onSongChanged(int i) {
    _timer?.cancel();
    _timer = null;
    _previewTimer?.cancel(); // 换歌打断试听(和弦上下文变了)
    _previewTimer = null;
    _setWakelock(false); // 换歌 = 停下,屏幕恢复正常(新歌默认不播,要按 ▶ 才再亮)
    _accumulateSec(); // 把正在播放的这段时间结进【旧歌】的 _totalSec
    final p = _prefs;
    // 切走前先把【当前这首】(还没换的 _selected)的速度、AB、累计打卡都存下来——下次回来才接得上。
    if (p != null) {
      p.setTempo(songs[_selected].id, _tempo);
      p.setAb(songs[_selected].id, _markerA, _markerB);
      p.setLoops(songs[_selected].id, _totalLoops);
      p.setSec(songs[_selected].id, _totalSec);
    }
    setState(() {
      _playing = false;
      _selected = i;
      _idx = 0;
      _slot = 0;
      _loops = 0; // 换歌重新计数
      _totalLoops = p?.getLoops(songs[i].id) ?? 0; // 新歌的累计遍数(没练过 = 0)
      _totalSec = p?.getSec(songs[i].id) ?? 0; // 新歌的累计秒数
      _playStart = null; // 不在播,清掉计时起点
      _inCountIn = false; // 换歌取消可能进行中的预备拍
      _everPlayed = false; // 新歌从头算"还没正式开始",下次按 ▶ 会重新数预备拍
      _markerA = null; // 换歌清空 AB(行下标按某首歌的行算,不能跨歌保留;AB 只在启动时恢复,不随切换蹦出来吓人)
      _markerB = null;
      // 切到新歌:用它【上次调到的速度】(没调过就原速)——每首歌记住自己的速度,来回切不丢。
      _tempo = p?.getTempo(songs[i].id) ?? songs[i].tempo;
      _rebuildFlat();
      _lastLine = _lineOfChord.isNotEmpty ? _lineOfChord[0] : 0;
    });
    // 切完记下新的歌下标(下次启动直接进这首)。
    p?.setSongIndex(i);
  }

  /// 拖滑块调速。正在播放时,旧 Timer.periodic 的间隔是【创建那一刻】就定死的、改 _tempo 它不知道,
  /// 所以必须 cancel 掉、用新的 _halfBeat 再起一个(下一个槽就按新速度来)。
  /// 不归零位置(_idx/_slot 不动)、也不立刻补响一声——否则会跟刚才那下叠在一起。
  /// 暂停时调也没事:只更新 _tempo,下次按 ▶ 自然用新速度。
  void _setTempo(int v) {
    if (v == _tempo) return;
    setState(() => _tempo = v);
    _restartTimerIfPlaying(); // 速度变了,定时器间隔也要跟着换
  }

  /// 正在播放时重启定时器:cancel 旧的、按当前 _halfBeat 起新的。
  /// 手动调速(_setTempo)和自动提速(_applyRamp)共用——改了 _tempo 都得这么换一下间隔。
  void _restartTimerIfPlaying() {
    if (_playing) {
      _timer?.cancel();
      _startTimer();
    }
  }

  /// 自动提速:每过一遍 +3 BPM、封顶原速(nextRampTempo 算)。到原速不再涨。改了 _tempo 要重启定时器。
  /// 只在 _rampOn 开着、且循环真正完成一遍(整曲到尾 / AB 到 B)时调。
  void _applyRamp() {
    final nt = nextRampTempo(_tempo, songs[_selected].tempo);
    if (nt != _tempo) {
      _tempo = nt;
      _restartTimerIfPlaying();
    }
  }

  /// 切"自动提速"开关。播放中切也立刻生效(下一遍循环完成时就提速)。同时存下来(跨歌偏好)。
  void _toggleRamp() {
    setState(() => _rampOn = !_rampOn);
    _prefs?.setRamp(_rampOn);
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
          _totalLoops++; // 累计打卡也 +1(跨会话)
          if (_rampOn) _applyRamp(); // 自动提速:每过一遍 +3、到原速停
        } else if (_idx + 1 >= _flat.length) {
          _idx = 0;
          _loops++;
          _totalLoops++; // 累计打卡也 +1(跨会话)
          if (_rampOn) _applyRamp(); // 自动提速:每过一遍 +3、到原速停
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
  /// 走一下:该响就响 + 刷新界面。这里【不】改 _slot/_idx/_inCountIn —— 推进放 _onTimerTick 里、在"下一槽"之前做。
  /// 因为 setState 延迟到下一帧才重画:若这边 setState 完就改值,重画读到的会是改后的值,扫弦会比声音快半拍(踩过的坑)。
  ///
  /// 响声策略(三态):
  /// - 预备拍(_inCountIn):只敲嗒声倒计时(要清晰,不掺扫弦声)。
  /// - 正式播放 + 扫弦声开:按这一槽的扫弦方向(下/上)播【当前和弦】的扫弦声,代替嗒声
  ///   (下扫那下本身就是每个正拍的标记,再叠嗒声会糊成一片;休止槽静音)。
  /// - 正式播放 + 扫弦声关:退回节拍器(正拍嗒、槽0 重音)——老行为。
  void _tick() {
    if (_inCountIn) {
      if (_slot.isEven) widget.audio.playClick(accent: _slot == 0);
    } else if (_strumSoundOn && _flat.isNotEmpty && _idx < _flat.length) {
      final dir = _strumDirForCurrentSlot();
      if (dir == StrumDir.down) {
        widget.audio.playChord(_flat[_idx]); // 当前和弦=_flat[_idx](推进已在 _onTimerTick 里做完)
      } else if (dir == StrumDir.up) {
        widget.audio.playChord(_flat[_idx], up: true);
      }
      // StrumDir.rest:休止,静音不响
    } else {
      if (_slot.isEven) widget.audio.playClick(accent: _slot == 0);
    }
    setState(() {}); // 刷新:练习栏(倒计时数字 / 扫弦型)、和弦贴片、当前行高亮
    if (!_inCountIn) _maybeScrollToCurrentLine();
  }

  /// 当前节奏型在当前槽(_slot)该往哪个方向扫。每拍现算(不缓存):节奏型是 build 里能改的,
  /// 缓存了容易跟界面对不上;这里几微秒的事,现算最稳。
  StrumDir _strumDirForCurrentSlot() {
    final bpc = songs[_selected].beatsPerChord;
    final patterns = patternsFor(bpc);
    final pattern = patterns[_patternIndex.clamp(0, patterns.length - 1)];
    final grid = pattern.grid(bpc);
    if (_slot >= 0 && _slot < grid.length) return grid[_slot];
    return StrumDir.rest;
  }

  /// 试听一段节奏型:用独立定时器按固定 90 BPM 半拍粒度,把所选节奏型的 grid 走一遍,
  /// 播【当前和弦】(或第一个和弦)的扫弦(下/上,休止静音)。没在播放时点节奏型芯片触发——
  /// 播放中不试听(那时你直接就听到它了)。换节奏型 / 开始正式播放 / 换歌 / 退出都会打断它。
  void _previewPattern(int patternIndex) {
    _previewTimer?.cancel(); // 上一段没放完又点新的:打断、重放新的
    final bpc = songs[_selected].beatsPerChord;
    final patterns = patternsFor(bpc);
    final pat = patterns[patternIndex.clamp(0, patterns.length - 1)];
    final grid = pat.grid(bpc);
    // 用当前和弦试听(弹到哪听哪个);_flat 万一空就退回 C(总在 chordShapes 里)。
    final chord = _flat.isNotEmpty
        ? _flat[_idx.clamp(0, _flat.length - 1)]
        : 'C';
    final halfBeat = Duration(milliseconds: (30000 / 90).round()); // 试听固定 90 BPM,清楚不赶
    _previewSlot = 0;
    _playPreviewSlot(grid, chord); // 立刻响第 0 槽,不用干等半拍
    _previewTimer = Timer.periodic(halfBeat, (_) {
      _previewSlot++;
      if (_previewSlot >= grid.length) {
        // 走完一小节:自停(一次性试听,不循环)。
        _previewTimer?.cancel();
        _previewTimer = null;
        return;
      }
      _playPreviewSlot(grid, chord);
    });
  }

  /// 试听里响一下当前槽:下扫 / 上扫播和弦声,休止静音。跟正式播放的扫弦响法一致。
  void _playPreviewSlot(List<StrumDir> grid, String chord) {
    if (_previewSlot < 0 || _previewSlot >= grid.length) return;
    final dir = grid[_previewSlot];
    if (dir == StrumDir.down) {
      widget.audio.playChord(chord);
    } else if (dir == StrumDir.up) {
      widget.audio.playChord(chord, up: true);
    }
    // StrumDir.rest:休止,静音不响
  }

  /// 切"扫弦声"开关。播放中切也立刻生效(下一槽就按新状态响)。同时存下来(跨歌偏好)。
  void _toggleStrumSound() {
    setState(() => _strumSoundOn = !_strumSoundOn);
    _prefs?.setStrumSound(_strumSoundOn);
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

  /// 把"从 _playStart 到现在"的秒数结进 _totalSec,然后清掉 _playStart。
  /// _playStart 为 null(没在播)就是 no-op。暂停 / 换歌 / 销毁时调,把计时落袋。
  void _accumulateSec() {
    final start = _playStart;
    if (start == null) return;
    final secs = DateTime.now().difference(start).inSeconds;
    _totalSec += secs;
    _playStart = null;
    if (secs > 0) {
      // 真正练了一会(>= 1 秒)→ 标记今天练过(去重),给统计页的日历 / 连续打卡用。
      // fire-and-forget,跟其它 prefs 写一个套路(不 await,不卡节拍)。
      _prefs?.markPracticedToday();
    }
  }

  /// 把当前歌的累计遍数 + 秒数存进持久化。跟 tempo 一个套路:暂停 / 换歌 / 销毁时兜底存,不在每拍写(怕写太勤)。
  void _saveStats() {
    _prefs?.setLoops(songs[_selected].id, _totalLoops);
    _prefs?.setSec(songs[_selected].id, _totalSec);
  }

  /// 把当前会话还没落盘的打卡补存:把 _playStart 到现在的秒数结进 _totalSec(还在播就重置 _playStart
  /// 让计时不停)、再 _saveStats 落盘。给 MainScaffold 在【切走练习 tab】时调——统计页现在是平级 tab,
  /// 不再靠"进页前 push"触发刷盘;不刷的话切过去读到的是旧值,会漏算刚练的这段。
  void flushStats() {
    _accumulateSec();
    if (_playing) _playStart = DateTime.now(); // 计时不停:补完这段后重新起算
    _saveStats();
  }

  /// 字号对话框:Slider 实时拖、歌词背后跟着变,松手就存(跨重启保留)。复位一键回 1.0。
  /// 用 StatefulBuilder 让对话框自己的 Slider 文字/百分比跟着拖动刷新;
  /// 同时调本页 setState,歌词区实时缩放(所见即所得,不用关对话框才看到效果)。
  void _showFontScaleDialog() {
    var v = _lyricScale;
    void apply(double nv) {
      v = nv;
      setState(() => _lyricScale = nv);
      _prefs?.setLyricScale(nv);
    }

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSt) {
            return AlertDialog(
              title: const Text('歌词字号'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 预览一行带和弦的词,用当前缩放,直观看到调完多大
                  Text(
                    '[C]Somewhere [G]over the [Am]rainbow',
                    style: Theme.of(ctx).textTheme.bodyLarge?.copyWith(
                      fontSize:
                          (Theme.of(ctx).textTheme.bodyLarge?.fontSize ?? 16) *
                          v,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${(v * 100).round()}%',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Slider(
                    min: 0.8,
                    max: 1.8,
                    divisions: 10, // 0.1 一档
                    value: v,
                    label: '${(v * 100).round()}%',
                    onChanged: (nv) => setSt(() => apply(nv)),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => setSt(() => apply(1.0)),
                  child: const Text('复位'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('完成'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 秒数格式化已上移为 models.dart 的 formatPracticeSec(顶栏 + 统计页共用)。

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
        items.add(SectionHeader(section.name!));
      }
      for (final line in section.lines) {
        // 关键:lineCursor 是循环【外】的变量、每轮 +1。onTap 是【以后点的时候】才执行的闭包,
        // 若直接写 () => _onLineTapped(lineCursor),它捕获的是 lineCursor 这个变量本身——
        // 等点的时候 lineCursor 早变成"总行数"了,点哪行都传同一个越界值(就是这次的 RangeError)。
        // 所以每轮单独存一份 final lineIdx,让闭包捕获这份固定的值。
        // (注:Dart 的 C 式 for(var i)循环变量倒是每轮独立的,这里 lineCursor 不是循环变量才中招。)
        final lineIdx = lineCursor;
        final marker = _markerForLine(lineIdx);
        final inRange = _abActive &&
            lineIdx >= _loopStartLine &&
            lineIdx <= _loopEndLine;
        items.add(
          LineView(
            line: line,
            lineKey: _lineKeys[lineIdx],
            isCurrentLine: lineIdx == currentLine,
            chordStart: chordCursor, // 这一行第 1 个和弦的全局下标
            currentChord: _idx,
            marker: marker,
            inRange: inRange,
            fontScale: _lyricScale,
            onTap: () => _onLineTapped(lineIdx),
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
            // FittedBox(scaleDown):文字太长(累计/时长一加就长)就自动缩字号塞进 24px 高的条,绝不溢出。
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                '$_tempo BPM${_tempo == song.tempo ? '' : (_tempo < song.tempo ? ' · 慢练' : ' · 加速')} · ${song.beatsPerChord}拍 · 本次 $_loops / 累计 $_totalLoops 遍 · 练了 ${formatPracticeSec(_totalSec)}${_rampOn && _tempo < song.tempo ? ' · 自动提速→${song.tempo}' : ''}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
        // 顶栏右侧图标:字号(调歌词大小)。统计、和弦速查挪成底导航 tab 了(第28步),不再占这。
        actions: [
          IconButton(
            icon: const Icon(Icons.format_size_rounded),
            tooltip: '歌词字号',
            onPressed: _showFontScaleDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // 顶部练习栏(吸顶):一排和弦卡 =【当前这一行】的和弦(弹到哪个、那张变大图高亮,其余小参考)+
          // 这一组扫到第几下(一排 ↓)+ 下一个和弦 + 调速滑块。卡跟当前行一一对应,不掺别行的和弦。
          PracticeBar(
            lineChords: lineChords,
            currentChordIndex: currentChordIndex,
            slot: _slot,
            beatsPerChord: song.beatsPerChord,
            strumGrid: strumGrid,
            patternNames: [for (final p in patterns) p.name],
            patternIndex: _patternIndex,
            onPatternChanged: (i) {
              setState(() => _patternIndex = i);
              _prefs?.setPatternIndex(i); // 节奏型是跨歌偏好,切了就存
              // 没在播放时点一下 → 试听一段这个节奏型(播放中能直接听到,不用试听)。
              if (widget.audio.isReady && !_playing) _previewPattern(i);
            },
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
            canPlay: widget.audio.isReady,
            onTogglePlay: _togglePlay,
            strumSoundOn: _strumSoundOn,
            onToggleStrumSound: _toggleStrumSound,
            rampOn: _rampOn,
            onToggleRamp: _toggleRamp,
            onChordTap: (c) => widget.audio.playChord(c), // 点和弦卡 → 听这个和弦的扫弦声
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
