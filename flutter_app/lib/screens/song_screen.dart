// 歌曲页:顶栏下拉选歌,正文铺出当前歌的每一段、每一行;节拍器一边打拍、一边推进"当前和弦"。
// 从 main.dart 拆出(第19步重构)。这里只放 SongScreen + 它的状态;界面部件在 widgets/,音频在 audio/。
//
// 这一版:歌曲页展示"歌词 + 和弦",顶栏下拉框选歌,练习栏调速行最左的 ▶ 按一下就按 BPM 嗒嗒响(节拍器)。
// 节拍器一边打拍、一边把"当前和弦"按拍数往前推进:顶部练习栏显示现在弹哪个、扫到第几下、下一个是什么;
// 歌词里当前和弦贴片反色点亮、当前行微微高亮并自动滚到屏幕中间。播到末尾循环回开头。
// 练习栏里:一排和弦卡 = 当前这一行的和弦,弹到哪个、那张就变大指法图高亮,其余小参考;卡跟当前行一一对应。
import 'dart:async'; // Timer(定时器)在这
import 'dart:typed_data'; // Uint8List:录音 WAV 字节

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart'; // openAppSettings:录音权限被永久拒绝时引去系统设置
import 'package:wakelock_plus/wakelock_plus.dart';

import '../audio/audio_constants.dart'; // kAudioSampleRate:音准监测喂 PitchDetector 的采样率
import '../audio/audio_engine.dart';
import '../audio/mic_capture.dart'; // 跟唱音准监测(完善Step7):开麦采人声
import '../audio/onset_detector.dart'; // 跟弹评分(完善Step8):麦扫弦起始检测
import '../audio/pitch_detector.dart'; // PitchDetector + frequencyToNote + NoteResult + centsStatusLabel
import '../audio/voice_recorder.dart'; // 跟唱录音(第49步)
import '../models.dart';
import '../prefs/app_preferences.dart';
import '../scoring/strum_scorer.dart'; // 跟弹评分(完善Step8):期望×onset → 命中/早/晚/准
import '../song_store.dart';
import '../widgets/lyric_view.dart';
import '../widgets/practice_bar.dart';
import 'add_song_screen.dart';

/// 歌曲页:顶栏下拉选歌,正文铺出当前歌的每一段、每一行。
/// 因为要"记住当前选的是哪首"+ 节拍器状态,这里用 StatefulWidget(带状态)。
///
/// audio 由外层 MainScaffold 注入并拥有(第28步:多个 tab 共用一份引擎,不在本页自建/自释放)。
class SongScreen extends StatefulWidget {
  final AudioEngine audio;
  final SongStore store; // 歌单(内置 + 用户自加);加 / 删用户歌时它 notify,本页下拉框刷新

  const SongScreen({required this.audio, required this.store, super.key});

  @override
  State<SongScreen> createState() => SongScreenState();
}

/// 本页现在是练琴 Hub 里 push 上来的全屏页:pop 回 Hub 时 dispose() 自动
/// _saveStats 落盘,统计页下次 reload() 读得到——不再需要外部 GlobalKey 戳。
class SongScreenState extends State<SongScreen> {
  /// 歌单(内置 + 用户自加)。从歌库读,不直接读顶层 songs——加 / 删用户歌能跟上(歌库会 notify)。
  /// 全文原来直接用 songs,这里加同名 getter 接管,旧代码 songs[...] 一行不用改。
  List<Song> get songs => widget.store.songs;

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
  // _inCountIn:正在数预备拍吗。两种情况置 true:① 从头第一次按 ▶ 数一小节(beatsPerChord×2 个槽);
  //   ② 自动循环回跳后数一小节【过渡拍】,给新手把手指换回第1和弦的时间(完善Step9 加)。
  // _everPlayed:这首歌这一轮"正式开始播"过了吗。只在"从头第一次按 ▶"给【开头那轮】预备拍;
  //   暂停后恢复不重复数。循环回跳的过渡拍由 _onTimerTick 直接 arm,不走这道闸。
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

  // 下拉框 items 缓存(第55步):歌单不变就不用重建 items,避免每 tick 都重建 26+ 个 DropdownMenuItem。
  List<DropdownMenuItem<int>>? _cachedDropdownItems;
  int _cachedSongCount = -1;

  // 语言筛选(第57步):'全部' / '英文' / '中文'。默认全部。切筛选时清 items 缓存。
  String _languageFilter = '全部';

  // 收藏筛选(第58步-2):'全部' / '收藏'。默认全部。
  String _favoriteFilter = '全部';

  // 难度筛选(完善Step4):null=全部、1=入门、2=初级、3=进阶。从 difficultyOf(song) 算。
  int? _difficultyFilter;

  // 歌曲搜索(第58步-1)。
  String _searchQuery = '';
  bool _showSearch = false;
  final TextEditingController _searchCtl = TextEditingController();

  /// 按当前语言+收藏+搜索词筛选后的歌单。
  List<Song> get _filteredSongs {
    var result = songs;
    // 语言筛选
    if (_languageFilter != '全部') {
      final reg = RegExp(r'[一-鿿]');
      final wantChinese = _languageFilter == '中文';
      result = result.where((s) => wantChinese ? reg.hasMatch(s.title) : !reg.hasMatch(s.title)).toList();
    }
    // 收藏筛选
    if (_favoriteFilter == '收藏') {
      result = result.where((s) => _favorites.contains(s.id)).toList();
    }
    // 搜索词筛选
    if (_searchQuery.isNotEmpty) {
      result = result.where((s) => s.title.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    }
    // 难度筛选
    if (_difficultyFilter != null) {
      result = result.where((s) => difficultyOf(s) == _difficultyFilter).toList();
    }
    return result;
  }

  // 收藏歌曲(第58步-2):id 集合,从 prefs 读写。
  Set<String> _favorites = {};

  // 移调(虚拟变调夹,半音偏移)。0 = 不移调(原音高);界面 Slider 限定 -6~+6。
  // 按歌存:每首歌贴合嗓音要的移调不一样,跟 tempo 一个套路,切歌不串。照旧按原和弦指法,
  // app 把扫弦声整体升 / 降这么多半音重新合成出来(双向都行,不像真变调夹只能升)。
  int _transpose = 0;

  // —— 跟唱录音(第49步)——
  // 录人声 →「听刚才」回放最后一段。MVP:只留最后一次(ephemeral,不持久化、不跨重启)。
  VoiceRecorder? _recorder; // 懒建(第一次录音时才 new);SongScreen 销毁时释放
  bool _recording = false; // 现在在录吗(切 mic/stop 图标 + 防重入)
  Uint8List? _takeWav; // 最近一次录音的完整 WAV(停录时套头生成);null = 还没录过 / 没录到

  // —— 跟唱音准监测(完善Step7):弹唱时实时显示唱到的音名 + 偏高/偏低,像人声版调音器 ——
  MicCapture? _monitorMic; // 懒建;SongScreen 销毁时释放
  StreamSubscription<Float64List>? _monitorSub;
  bool _monitorOn = false; // 现在在监测吗(切图标 + 显音高条)
  NoteResult? _sungNote; // 最近测到的音(null = 没在唱 / 太轻测不到)
  // 人声音域:男低 ~80Hz 到女高 ~1000Hz,覆盖常见演唱范围(跟调音器的 150-500 弦域区分开)。
  final PitchDetector _vocalDetector =
      const PitchDetector(minFrequency: 80, maxFrequency: 1000);

  // —— 跟弹评分(完善Step8):开麦听扫弦、逐下比对节拍打分,让新手看到练习的真正效果 ——
  // 评分中:静音扫弦声(Karplus-Strong 是宽带,会污染麦),只保留嗒声(切到带淡入、可滤的嘀声),
  // 麦那头 OnsetDetector 把嗒声滤掉、抓出扫弦;strum_scorer 把抓到的扫弦跟节拍比对。
  bool _scoring = false; // 评分开关(只在未播放时可切 —— 播放中置灰,免得麦中途起漏开头)
  bool _scoringSessionActive = false; // 当前是否在一次评分播放中(▶ 起、⏸ 止)
  MicCapture? _scoreMic; // 评分用麦(跟 _monitorMic / _recorder 互斥共享一个设备麦)
  StreamSubscription<Float64List>? _scoreSub;
  OnsetDetector? _scoreOnset; // 懒建;reset 后复用
  final Stopwatch _scoreStopwatch = Stopwatch(); // 评分统一时钟(▶ 起,跨调速 / 循环不重置)
  final List<double> _expectedTimes = []; // 每下「该扫」的时刻(秒,stopwatch 时钟)
  final List<double> _onsetTimes = []; // 检出的扫弦时刻(秒,stopwatch 时钟,未减延迟)
  bool _scoreMicReady = false; // 第一个 chunk 到了没(没到不记 expected —— 防漏开头那几下)
  ScoreResult? _liveResult; // 实时累计分(给 live 条;只含窗口已关闭的 expected)
  ScoreResult? _lastSummary; // 停播时弹的总结
  double _scoreLatency = 0.10; // 延迟校准(秒,从 prefs 读;总结里可调)

  // —— 分段 AB 循环 ——
  // _markerA / _markerB:用户在歌词上点的两个"循环点"(行下标)。两个都标好 → 引擎到 B 行末尾跳回 A 行开头反复。
  // 只标了 A(_markerB 仍 null)= 还没成区间,只在那一行显示 A 徽标。换歌清空(行下标是按某首歌的行算的,不能跨歌保留)。
  int? _markerA;
  int? _markerB;

  // —— 全屏练习模式:隐藏自己的 AppBar,沉浸看歌词。
  // (本页现在是练琴 Hub 里 push 上来的全屏页,底导航本就被路由盖住,所以全屏只管自己的 AppBar。)
  bool _fullscreen = false;

  void _toggleFullscreen() {
    setState(() => _fullscreen = !_fullscreen);
  }

  // 持久化:记住上次的歌 / 速度 / 节奏型 / AB 区间。initState 里异步加载(_loadPrefs),
  // 没加载好之前是 null —— 各保存点都用 ?. 守住,加载好才真写。
  AppPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChanged); // 歌单变(加 / 删用户歌)→ 刷新下拉框
    _rebuildFlat(); // 先把当前歌拍扁,界面第一次画就能显示"现在弹 第1个和弦"
    _tempo = songs[_selected].tempo; // 默认原速(late 字段必须在第一次被读之前赋上值)
    // 音频引擎由 MainScaffold 在 app 启动时统一 init(本页只调它的方法),这里不再 _initAudio。
    _loadPrefs(); // 异步读上次的歌/速度/节奏型/AB,读好再 reconcile(不卡首帧:首帧先用默认值画)
  }

  /// 歌单变了(加 / 删用户歌):刷新下拉框。_selected 可能越界(删歌时),夹回合法范围。
  void _onStoreChanged() {
    _cachedDropdownItems = null; // 歌单变了,清缓存重建
    if (!mounted || songs.isEmpty) return;
    setState(() {
      _selected = _selected.clamp(0, songs.length - 1);
    });
  }

  /// 切语言筛选(第57步):清 items 缓存、防 _selected 越界。当前歌不在筛选结果中→自动跳到筛后第一首。
  void _setLanguageFilter(String v) {
    if (v == _languageFilter) return;
    setState(() {
      _languageFilter = v;
      _cachedDropdownItems = null;
      _reconcileFilteredSelection();
    });
  }

  /// 切收藏筛选(第58步-2):跟语言筛选同套路,选收藏时把不在收藏里的歌跳过。
  void _setFavoriteFilter(String v) {
    if (v == _favoriteFilter) return;
    setState(() {
      _favoriteFilter = v;
      _cachedDropdownItems = null;
      _reconcileFilteredSelection();
    });
  }

  /// 切难度筛选(完善Step4):再点当前档 = 取消(回全部)。同 _setFavoriteFilter 套路。
  void _setDifficultyFilter(int? v) {
    if (v == _difficultyFilter) return;
    setState(() {
      _difficultyFilter = v;
      _cachedDropdownItems = null;
      _reconcileFilteredSelection();
    });
  }

  /// 筛选变了→当前歌可能不在新筛选结果里,自动跳到第一首。
  void _reconcileFilteredSelection() {
    final filtered = _filteredSongs;
    if (filtered.isEmpty) return; // 全不匹配时不动(比如搜了不存在的歌);下拉框会空但不会越界
    final current = songs[_selected];
    final idx = filtered.indexOf(current);
    if (idx == -1) {
      _onSongChanged(songs.indexOf(filtered.first));
    }
  }

  /// 搜索框输入变化(第58步-1):更新查询词、刷新下拉框缓存、防越界。
  void _onSearchChanged(String v) {
    setState(() {
      _searchQuery = v;
      _cachedDropdownItems = null;
      _reconcileFilteredSelection();
    });
  }

  /// 展开/收起搜索框(第58步-1)。
  void _toggleSearch() {
    setState(() {
      _showSearch = !_showSearch;
      if (!_showSearch) {
        _searchCtl.clear();
        _onSearchChanged('');
      }
    });
  }

  /// 切收藏状态(第58步-2):点心形图标 → 收藏/取消当前歌。
  void _toggleFavorite() {
    final id = songs[_selected].id;
    setState(() {
      if (_favorites.contains(id)) {
        _favorites.remove(id);
      } else {
        _favorites.add(id);
      }
    });
    _prefs?.setFavorites(_favorites.toList());
  }

  /// 异步读持久化偏好,读好把状态 reconcile 到上次的值(上次的歌、那首歌的速度、节奏型、AB)。
  /// 不阻塞首帧:首帧用默认值(歌0 / 原速)先画,这里读完再 setState 切过去。
  /// 测试环境 SharedPreferences 是自动 mock 的空库 → 读出来都是默认值,reconcile 等于没动。
  Future<void> _loadPrefs() async {
    final p = await AppPreferences.load();
    if (!mounted) return;
    setState(() {
      _prefs = p;
      // 上次选哪首按【id】存(第45步起):加 / 删用户歌不会让"上次选哪首"串位。旧版按下标存,这里一次性迁移。
      var id = p.getSelectedSongId();
      if (id == null) {
        // 旧版按下标存:读回下标 → 换算成那首歌的 id 存下,以后直接走 id。
        final legacy = p.getLegacySongIndex(_selected).clamp(0, songs.length - 1);
        id = songs[legacy].id;
        p.setSelectedSongId(id); // fire-and-forget 一次性迁移(跟其它 prefs 写一个套路)
      }
      final found = songs.indexWhere((s) => s.id == id);
      _selected = (found < 0 ? _selected : found).clamp(0, songs.length - 1);
      // clamp 防万一存了个越界值(节奏型以后还会加);上界按当前歌的节奏型数量动态取,别写死成数字。
      _patternIndex = p
          .getPatternIndex(_patternIndex)
          .clamp(0, patternsFor(songs[_selected].beatsPerChord).length - 1);
      _strumSoundOn = p.getStrumSound(true);
      _rampOn = p.getRamp();
      _scoring = p.getScoring(); // 完善Step8:上次评分开关状态
      _scoreLatency = p.getScoreLatency(); // 完善Step8:上次调的延迟校准
      _lyricScale = p.getLyricScale(1.0).clamp(0.8, 1.8); // Slider 区间,防存了个越界值
      _favorites = p.getFavorites(); // 收藏列表(第58步-2),跨重启保留
      _rebuildFlat(); // 按载入的歌重新拍扁(歌曲可能从 0 变成上次的下标)
      _tempo = p.getTempo(songs[_selected].id) ?? songs[_selected].tempo;
      _transpose = p.getTranspose(songs[_selected].id); // 这首歌上次的移调(没存过 = 0)
      _totalLoops = p.getLoops(songs[_selected].id); // 上次这首歌累计练的遍数
      _totalSec = p.getSec(songs[_selected].id); // 上次这首歌累计练的秒数
      _lastLine = _lineOfChord.isNotEmpty ? _lineOfChord[0] : 0;
      // AB 是按歌存的行下标:万一 songs 改过、行数变了,越界的丢弃(否则后面 _loopStartLine 会越界)。
      final ab = p.getAb(songs[_selected].id);
      _markerA = _validLine(ab?.a);
      _markerB = _validLine(ab?.b);
    });
    // 载入的移调 ≠ 0 → 预生成对应偏移的扫弦声源(后台;没好之前 playChord 回退原音高,不静音)。
    widget.audio.prepareTranspose(_transpose);
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
    widget.store.removeListener(_onStoreChanged); // 页面销毁:别再收歌库通知
    _searchCtl.dispose(); // 搜索框控制器(第58步-1)
    // 页面销毁前最后存一次当前歌的速度(滑块拖动时不存、怕写太勤;走这里兜底)。
    // ramp 开着时存原速:别把自动提速的值落盘,否则下次进来直接原速、渐进提速失效。
    _accumulateSec(); // 把正在播放的尾段时间结进 _totalSec(没在播就是 no-op)
    _prefs?.setTempo(songs[_selected].id, _rampOn ? songs[_selected].tempo : _tempo);
    _saveStats(); // 兜底存累计遍数 + 秒数
    _setWakelock(false); // 离开页面:释放屏幕常亮,别一直亮着耗电
    // 页面销毁时收尾:停闹钟、释放预览定时器。_audio 不在这释放——它归 MainScaffold 拥有。
    _timer?.cancel();
    _previewTimer?.cancel();
    _recorder?.dispose(); // 跟唱录音器:停录 + 释放麦(SongScreen 销毁 = app 退出,IndexedStack 保活)
    _monitorSub?.cancel(); // 跟唱音准监测:停订阅(dispose 时 element 已 defunct,不能 setState,直接清)
    _monitorMic?.dispose(); // 释放麦
    _scoreSub?.cancel(); // 跟弹评分(完善Step8):停订阅 + 释放评分麦
    _scoreMic?.dispose();
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
  ///
  /// 完善Step8:评分开着的话,起播时先开麦(预备拍期间热起来,补偿输入延迟);停播时算总结、弹卡。
  /// 麦开不了(权限拒 / start 失败)→ 关掉评分、退回普通练习(嗒声+扫弦声),不静默 0%。
  Future<void> _togglePlay() async {
    if (_playing) {
      _timer?.cancel();
      _timer = null;
      _accumulateSec(); // 暂停:把这段播放时间结进 _totalSec
      _saveStats(); // 暂停时存一次累计(遍数 + 秒数),免得退出丢失
      if (_scoringSessionActive) {
        await _stopScoringSession(); // 停麦 + 算总结 + 弹卡
      }
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
      // 评分:起播时开麦(预备拍期间热起来)。开不了 → 关评分,下面照常按普通模式起拍。
      if (_scoring) {
        final ok = await _startScoringSession();
        if (!mounted) return;
        if (!ok) {
          setState(() => _scoring = false);
          _prefs?.setScoring(false);
        }
      }
      _playStart = DateTime.now(); // 记下开始播放的时刻(计时用)
      // 立刻响当下这一下(预备拍第1下 或 恢复处的槽),不用干等半拍。
      _tick();
      _startTimer();
    }
    _setWakelock(!_playing); // 要播就屏幕常亮、要停就恢复正常(_playing 还没翻,!它 = 新状态)
    if (mounted) setState(() => _playing = !_playing);
  }

  /// 换歌:速度可能变了,先停掉节拍器、把位置归零,再按新歌拍扁数据,免得还按上一首的旧结构走。
  void _onSongChanged(int i) {
    _timer?.cancel();
    _timer = null;
    _previewTimer?.cancel(); // 换歌打断试听(和弦上下文变了)
    _previewTimer = null;
    _abortScoringSession(); // 换歌 = 停这次评分 take(静默,不弹总结)
    _setWakelock(false); // 换歌 = 停下,屏幕恢复正常(新歌默认不播,要按 ▶ 才再亮)
    _accumulateSec(); // 把正在播放的这段时间结进【旧歌】的 _totalSec
    final p = _prefs;
    // 切走前先把【当前这首】(还没换的 _selected)的速度、移调、AB、累计打卡都存下来——下次回来才接得上。
    if (p != null) {
      p.setTempo(songs[_selected].id, _rampOn ? songs[_selected].tempo : _tempo);
      p.setTranspose(songs[_selected].id, _transpose);
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
      _transpose = p?.getTranspose(songs[i].id) ?? 0; // 新歌的移调(没存过 = 0)
      _rebuildFlat();
      _lastLine = _lineOfChord.isNotEmpty ? _lineOfChord[0] : 0;
    });
    // 切完记下新选的歌【id】(下次启动直接进这首;按 id 存,加 / 删别的歌不会串位)。
    p?.setSelectedSongId(songs[i].id);
    // 新歌移调 ≠ 0 → 预生成对应声源(跟 _loadPrefs 一个套路)。
    widget.audio.prepareTranspose(_transpose);
  }

  /// 点"添加自己的歌":开表单 → 校验通过拿到 Song → 加进歌库 → 切到这首新歌。
  Future<void> _openAddSong() async {
    final created = await Navigator.of(context).push<Song>(
      MaterialPageRoute(builder: (_) => const AddSongScreen()),
    );
    if (!mounted || created == null) return; // 取消了 / 页面已不在
    widget.store.add(created);
    // 加完切到这首新歌(它被追加到歌单末尾),走完整换歌流程(停拍、读新歌的偏好)。
    if (songs.isNotEmpty) _onSongChanged(songs.length - 1);
  }

  /// 编辑当前这首用户歌:开表单(回填)→ 拿到改后的 Song → 更新歌库 → 按新内容重拍扁。
  Future<void> _openEditSong() async {
    final current = songs[_selected];
    if (!widget.store.isUserSong(current)) return; // 内置歌不可改(兜一道,图标本就不出)
    // 编辑期间停掉节拍器(不然表单开着、后台还按旧内容打拍)。
    if (_playing) {
      _timer?.cancel();
      _timer = null;
      _accumulateSec();
      _setWakelock(false);
    }
    _previewTimer?.cancel();
    _previewTimer = null;
    _abortScoringSession(); // 编辑 = 停这次评分 take(静默)
    final edited = await Navigator.of(context).push<Song>(
      MaterialPageRoute(builder: (_) => AddSongScreen(initial: current)),
    );
    if (!mounted || edited == null) return; // 取消了 / 页面已不在
    widget.store.update(edited);
    final p = _prefs;
    setState(() {
      _playing = false;
      _idx = 0;
      _slot = 0;
      _loops = 0; // 内容可能变了,本次遍数从头计
      _markerA = null; // 行结构可能变,旧 AB 失效
      _markerB = null;
      _inCountIn = false;
      _everPlayed = false;
      _rebuildFlat();
      _tempo = edited.tempo; // 原速可能改了
      _lastLine = _lineOfChord.isNotEmpty ? _lineOfChord[0] : 0;
    });
    p?.setTempo(edited.id, edited.tempo); // 新原速落盘(覆盖旧的"上次速度")
    p?.setAb(edited.id, null, null); // 行结构可能变,清旧 AB
  }

  /// 删除当前这首用户歌:确认 → 从歌库移除(顺带清它的偏好)→ 切回第一首。内置歌不可删。
  Future<void> _deleteCurrentSong() async {
    final current = songs[_selected];
    if (!widget.store.isUserSong(current)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这首歌?'),
        content: Text('「${current.title}」删掉就找不回来了。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // 停播放(歌要删了,不结计时、不存偏好——remove 会清掉)。
    _timer?.cancel();
    _timer = null;
    _previewTimer?.cancel();
    _previewTimer = null;
    _playStart = null;
    _abortScoringSession(); // 删除 = 停这次评分 take(静默)
    if (_playing) _setWakelock(false);
    widget.store.remove(current.id); // notify → _onStoreChanged 把 _selected 夹回合法范围
    if (!mounted || songs.isEmpty) return;
    // 切回第一首(内置歌,一定在)。不走 _onSongChanged:它会"存旧歌偏好",但旧歌已删、下标也挪了——
    // 那样会把别的歌的偏好写花。这里直接重置到第 0 首。
    final p = _prefs;
    setState(() {
      _playing = false;
      _selected = 0;
      _idx = 0;
      _slot = 0;
      _loops = 0;
      _markerA = null;
      _markerB = null;
      _inCountIn = false;
      _everPlayed = false;
      _rebuildFlat();
      _tempo = p?.getTempo(songs[0].id) ?? songs[0].tempo;
      _totalLoops = p?.getLoops(songs[0].id) ?? 0;
      _totalSec = p?.getSec(songs[0].id) ?? 0;
      _lastLine = _lineOfChord.isNotEmpty ? _lineOfChord[0] : 0;
    });
    p?.setSelectedSongId(songs[0].id);
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

  /// 设移调(虚拟变调夹):钳到 -6~+6、存下来(按歌)、预生成对应偏移的扫弦声源。
  /// 不用停节拍器:声源在后台生成,没好之前 playChord 回退原音高兜底、不静音,好了下一拍就准。
  void _setTranspose(int v) {
    final clamped = v.clamp(-6, 6);
    if (clamped == _transpose) return;
    setState(() => _transpose = clamped);
    _prefs?.setTranspose(songs[_selected].id, clamped);
    widget.audio.prepareTranspose(clamped);
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
          _inCountIn = true; // 循环过渡:回跳后嗒满1小节再开下一遍(_slot 已是0;_tick 会播预备拍第1拍)
        } else if (_idx + 1 >= _flat.length) {
          _idx = 0;
          _loops++;
          _totalLoops++; // 累计打卡也 +1(跨会话)
          if (_rampOn) _applyRamp(); // 自动提速:每过一遍 +3、到原速停
          _inCountIn = true; // 循环过渡:同上
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
  /// 响声策略(完善Step8 增「评分」态):
  /// - 预备拍(_inCountIn):只敲嗒声倒计时(评分开着也用嘀声 + 淡入,免得正拍时音色突变)。
  /// - 评分中(_scoring 且正式播放):静音扫弦(Karplus-Strong 宽带、会污染麦),只敲可滤的嘀声节拍;
  ///   每下「该扫」(dir != rest)记一个期望时刻(给 scorer 比对),并刷新实时分。
  /// - 正式播放 + 扫弦声开:按这一槽的扫弦方向播当前和弦的扫弦声,代替嗒声(休止静音)。
  /// - 正式播放 + 扫弦声关:退回节拍器(正拍嗒、槽0 重音)——老行为。
  void _tick() {
    if (_inCountIn) {
      if (_slot.isEven) widget.audio.playClick(accent: _slot == 0, scoring: _scoring);
    } else if (_scoring) {
      // 评分:静音扫弦、敲嘀声(带淡入,麦那头陷波能剔掉),记期望 + 刷新实时分。
      if (_slot.isEven) widget.audio.playClick(accent: _slot == 0, scoring: true);
      if (_scoreMicReady && _flat.isNotEmpty && _idx < _flat.length) {
        if (_strumDirForCurrentSlot() != StrumDir.rest) {
          _expectedTimes.add(_scoreStopwatch.elapsedMilliseconds / 1000.0);
        }
      }
      _refreshLiveScore();
    } else if (_strumSoundOn && _flat.isNotEmpty && _idx < _flat.length) {
      final dir = _strumDirForCurrentSlot();
      if (dir == StrumDir.down) {
        widget.audio.playChord(_flat[_idx], semis: _transpose);
      } else if (dir == StrumDir.up) {
        widget.audio.playChord(_flat[_idx], up: true, semis: _transpose);
      }
      // 休止:静音不响
    } else {
      if (_slot.isEven) widget.audio.playClick(accent: _slot == 0);
    }
    setState(() {});
    if (!_inCountIn) _maybeScrollToCurrentLine();
  }

  /// 当前节奏型在当前槽(_slot)该往哪个方向扫。每拍现算(不缓存):现算最稳。
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

  /// 试听里响一下当前槽:下扫 / 上扫播和弦声,休止静音。跟正式播放的扫弦响法一致(带当前移调)。
  void _playPreviewSlot(List<StrumDir> grid, String chord) {
    if (_previewSlot < 0 || _previewSlot >= grid.length) return;
    final dir = grid[_previewSlot];
    if (dir == StrumDir.down) {
      widget.audio.playChord(chord, semis: _transpose);
    } else if (dir == StrumDir.up) {
      widget.audio.playChord(chord, up: true, semis: _transpose);
    }
    // StrumDir.rest:休止,静音不响
  }

  /// 切"扫弦声"开关。播放中切也立刻生效(下一槽就按新状态响)。同时存下来(跨歌偏好)。
  void _toggleStrumSound() {
    setState(() => _strumSoundOn = !_strumSoundOn);
    _prefs?.setStrumSound(_strumSoundOn);
  }

  /// 当前行变了,就把它滚到屏幕中间。每拍都调,但只有跨行才真滚,不会一拍一抖。
  /// 第55步:加防抖——两次滚动间隔 < 300ms 时用瞬时跳转(jumpTo),避免动画叠加抖动。
  DateTime? _lastScrollTime;

  void _maybeScrollToCurrentLine() {
    if (_flat.isEmpty || _idx >= _lineOfChord.length) return;
    final li = _lineOfChord[_idx];
    if (li == _lastLine) return;
    _lastLine = li;
    if (li >= _lineKeys.length) return;
    final ctx = _lineKeys[li].currentContext;
    if (ctx != null) {
      final now = DateTime.now();
      final rapid = _lastScrollTime != null &&
          now.difference(_lastScrollTime!).inMilliseconds < 300;
      _lastScrollTime = now;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: rapid ? Duration.zero : const Duration(milliseconds: 250),
      );
    }
  }

  /// 构建下拉框 items,仅歌单变化时重建(第55步缓存:避免每 tick 重建 26+ DropdownMenuItem)。
  /// 第57步:改用 _filteredSongs,筛选后只显示对应语言的歌。
  List<DropdownMenuItem<int>> _buildDropdownItems(ThemeData theme) {
    final filtered = _filteredSongs;
    // 缓存 key = 歌单长度 + 筛选值,确保切筛选时重建
    if (_cachedDropdownItems != null && songs.length == _cachedSongCount) {
      return _cachedDropdownItems!;
    }
    _cachedSongCount = songs.length;
    _cachedDropdownItems = [
      for (final s in filtered)
        DropdownMenuItem(
          value: songs.indexOf(s), // 映射回真实下标
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(s.title, style: TextStyle(color: theme.colorScheme.onSurface)),
                const SizedBox(width: 8),
                // 难度标签(完善Step4):帮新手一眼看出从哪首入手。
                Text(
                  difficultyLabel(difficultyOf(s)),
                  style: TextStyle(fontSize: 11, color: theme.colorScheme.primary, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      DropdownMenuItem(
        value: -1,
        child: Row(
          children: [
            Icon(Icons.add, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Text('添加自己的歌', style: TextStyle(color: theme.colorScheme.primary)),
          ],
        ),
      ),
    ];
    return _cachedDropdownItems!;
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
      // 第55步:记录这首歌上次练习日期(今天的 ISO 日期),给统计页"上次练习"显示用。
      _prefs?.setLastPracticed(
        songs[_selected].id,
        practiceDayKey(DateTime.now()),
      );
      // 第58步-3:增量累加今天的练琴秒数(给每日目标用)。
      final today = practiceDayKey(DateTime.now());
      final prev = _prefs?.getTodaySec(today) ?? 0;
      _prefs?.setTodaySec(today, prev + secs);
    }
  }

  /// 把当前歌的累计遍数 + 秒数存进持久化。跟 tempo 一个套路:暂停 / 换歌 / 销毁时兜底存,不在每拍写(怕写太勤)。
  void _saveStats() {
    _prefs?.setLoops(songs[_selected].id, _totalLoops);
    _prefs?.setSec(songs[_selected].id, _totalSec);
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

  /// 移调(虚拟变调夹)对话框:Slider 拖 -6~+6 半音,松手就存(按歌、跨重启保留)。复位一键回 0。
  /// 用 StatefulBuilder 让对话框里的文案 / 滑块跟着拖动刷新;同时调本页 setState,信息行实时变。
  /// 解释:照旧按原和弦指法(还是 C/G/Am/F),app 把扫弦声整体升 / 降这么多半音重新合成——
  /// 不用学新和弦(尤其大横按),声音却贴合自己嗓音。双向都行(真变调夹只能升)。
  void _showTransposeDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSt) {
            final sign = _transpose > 0 ? '+' : '';
            return AlertDialog(
              title: const Text('移调(虚拟变调夹)'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _transpose == 0 ? '原调(不移调)' : '$sign$_transpose 半音',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(ctx).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '照旧按原和弦指法,扫弦声整体升 / 降这么多半音',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Slider(
                    min: -6,
                    max: 6,
                    divisions: 12, // 半音一档
                    value: _transpose.toDouble(),
                    label: '${_transpose > 0 ? '+' : ''}$_transpose',
                    onChanged: (nv) {
                      final v = nv.round();
                      setSt(() {}); // 刷新对话框文案
                      _setTranspose(v); // 钳到范围、存、预生成声源、刷信息行
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setSt(() {});
                    _setTranspose(0);
                  },
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

  // —— 跟唱录音(第49步):录人声 →「听刚才」回放最后一段 ——
  // 跟练习的节拍器 / 扫弦声互不干扰:录音器只管开麦收 PCM、回放只管播 WAV,都不碰节拍推进逻辑。
  VoiceRecorder _ensureRecorder() => _recorder ??= VoiceRecorder();

  /// 按一下 mic:正在录 → 停(生成 WAV 存下);没在录 → 申请权限 + 开录。
  Future<void> _toggleRecord() async {
    if (_recording) {
      await _stopRecord();
    } else {
      await _startRecord();
    }
  }

  /// 开录:先要麦克风权限(没有就提示;永久拒绝给「去设置」入口)。权限 ok → 清缓冲开麦。
  Future<void> _startRecord() async {
    if (_monitorOn) _stopMonitor(); // 互斥:录音要占麦,先停音准监测
    final rec = _ensureRecorder();
    final granted = await rec.requestPermission();
    if (!granted) {
      if (!mounted) return;
      final denied = await rec.isPermanentlyDenied();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('需要麦克风权限才能录音'),
          action: denied
              ? SnackBarAction(label: '去设置', onPressed: openAppSettings)
              : null,
        ),
      );
      return;
    }
    final started = await rec.start();
    if (!started) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('开录失败,再试一次')),
      );
      return;
    }
    setState(() => _recording = true); // 切成 stop 图标 + 信息行显「录音中」
  }

  /// 停录:关麦、取走 PCM、套 WAV 头存成 _takeWav。没录到(缓冲空)给个提示、不清掉旧 take。
  Future<void> _stopRecord() async {
    final rec = _recorder;
    if (rec == null) return;
    final pcm = await rec.stop();
    Uint8List? wav;
    if (pcm != null && pcm.isNotEmpty) {
      wav = wavFromPcm16(pcm); // 套标准 WAV 头(纯函数,可测)
    }
    if (!mounted) return;
    setState(() {
      _recording = false;
      if (wav != null) _takeWav = wav; // 录到了 → 覆盖旧的(只留最后一次)
    });
    if (wav == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没录到,再试一次')),
      );
    }
  }

  /// 「听刚才」:回放最近一次录音。
  void _playTake() {
    final wav = _takeWav;
    if (wav == null) return;
    widget.audio.playWavBytes(wav);
  }

  // —— 跟唱音准监测(完善Step7)——
  // 开麦采人声 → PitchDetector 测基频 → frequencyToNote 得音名 + cents → 实时显示偏高/偏低。
  // 跟录音互斥(都占麦):开监测先停录音。麦也会收到扫弦声(无回声消除,跟录音同问题),
  // 这是个"参考"不是"评分"——人声明亮时较准。装机才能真测(权限 / 真麦)。
  Future<void> _toggleMonitor() async {
    if (_monitorOn) {
      _stopMonitor();
      return;
    }
    if (_recording) await _stopRecord(); // 互斥:先停录音(同时占麦会失败)
    final mic = _monitorMic ??= MicCapture();
    final granted = await mic.requestPermission();
    if (!granted) {
      if (!mounted) return;
      final denied = await mic.isPermanentlyDenied();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('需要麦克风权限才能监测音准'),
          action: denied ? SnackBarAction(label: '去设置', onPressed: openAppSettings) : null,
        ),
      );
      return;
    }
    final started = await mic.start();
    if (!started) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('开麦失败,再试一次')));
      return;
    }
    _monitorSub = mic.samples.listen(_onMonitorSample);
    setState(() => _monitorOn = true);
  }

  /// 来了一段人声样本 → 测基频 → 更新音高条。测不到(太轻 / 没在唱)→ _sungNote 置 null。
  void _onMonitorSample(Float64List s) {
    final f = _vocalDetector.detect(s, kAudioSampleRate);
    if (!mounted) return;
    setState(() => _sungNote = f == null ? null : frequencyToNote(f));
  }

  void _stopMonitor() {
    _monitorSub?.cancel();
    _monitorSub = null;
    _monitorMic?.stop(); // fire-and-forget(跟 _recorder 一个套路)
    _monitorOn = false;
    _sungNote = null;
    if (mounted) setState(() {}); // 刷新图标 / 音高条;dispose 时 mounted=false 不刷
  }

  // —— 跟弹评分(完善Step8)——
  // 模型:每次 ▶(评分开)…⏸ = 一次评分 take,独立计时 + 独立 expected/onset 列表 + 独立总结。
  // 麦跟 _monitorMic / _recorder 共用一个设备麦 → 互斥:评分开着时,record / monitor 按钮已置灰,
  // 这里 _startScoringSession 再保险停一下它们。

  /// 切评分开关。只在未播放时可切(播放中按钮已置灰,这里再兜一道)。
  void _toggleScoring() {
    if (_playing) return;
    setState(() => _scoring = !_scoring);
    _prefs?.setScoring(_scoring);
  }

  /// 起一次评分 take:开麦 + 复位检测器/列表/时钟。返 false = 麦开不了(权限拒 / start 失败)。
  Future<bool> _startScoringSession() async {
    _stopMonitor(); // 互斥兜底(按钮本已禁用)
    if (_recording) await _stopRecord();
    final mic = _scoreMic ??= MicCapture();
    final granted = await mic.requestPermission();
    if (!granted) {
      if (!mounted) return false;
      final denied = await mic.isPermanentlyDenied();
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('需要麦克风权限才能跟弹评分'),
        action: denied ? SnackBarAction(label: '去设置', onPressed: openAppSettings) : null,
      ));
      return false;
    }
    _scoreOnset ??= OnsetDetector(sampleRate: kAudioSampleRate);
    _scoreOnset!.reset();
    _expectedTimes.clear();
    _onsetTimes.clear();
    _liveResult = null;
    _scoreMicReady = false;
    final started = await mic.start();
    if (!started) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('开麦失败,已关掉评分。检查权限后重试')),
      );
      return false;
    }
    _scoreSub?.cancel();
    _scoreSub = mic.samples.listen(_onScoreSample);
    _scoreStopwatch.reset();
    _scoreStopwatch.start();
    _scoringSessionActive = true;
    return true;
  }

  /// 停一次评分 take:停麦 + 算最终总结 + 弹总结卡(每 ▶…⏸ 一次总结)。
  Future<void> _stopScoringSession() async {
    _scoreSub?.cancel();
    _scoreSub = null;
    await _scoreMic?.stop();
    _scoreStopwatch.stop();
    _scoringSessionActive = false;
    _scoreMicReady = false;
    if (_expectedTimes.isEmpty) return; // 没正式记到期望(可能一开播就停)→ 不弹总结
    _lastSummary = score(
      expectedTimes: List.of(_expectedTimes),
      onsetTimes: List.of(_onsetTimes),
      tolerance: 0.18,
      latencyOffset: _scoreLatency,
    );
    if (mounted) _showScoreSummary(_lastSummary!);
  }

  /// 静默拆掉评分 take(换歌 / 编辑 / 删除 / 销毁路径用):停麦、清状态,【不】弹总结。
  void _abortScoringSession() {
    _scoreSub?.cancel();
    _scoreSub = null;
    _scoreMic?.stop(); // fire-and-forget
    _scoreStopwatch.stop();
    _scoringSessionActive = false;
    _scoreMicReady = false;
  }

  /// 麦来了一段样本 → 喂 OnsetDetector → 检出的 onset 累计进列表(同一 stopwatch 时钟,未减延迟)。
  /// 不每 chunk setState(节流到 _tick,免得麦回调太勤卡 UI)。
  void _onScoreSample(Float64List chunk) {
    final det = _scoreOnset;
    if (det == null || !_scoringSessionActive) return;
    if (!_scoreMicReady) _scoreMicReady = true; // 第一个 chunk 到了 → 之后 _tick 才开始记 expected
    final arrival = _scoreStopwatch.elapsedMilliseconds / 1000.0;
    final onsets = det.process(chunk, arrival);
    if (onsets.isNotEmpty) _onsetTimes.addAll(onsets);
  }

  /// 重算实时累计分:只纳入【窗口已关闭】的期望(now ≥ e + tolerance),免得最新的那下 onset 还没到
  /// 就先判漏、圆点闪一下。最新的等它的 onset 到了再转正。_tick 每槽调一次。
  static const double _scoreTolerance = 0.18; // 秒,跟 strum_scorer 默认一致
  void _refreshLiveScore() {
    if (!_scoringSessionActive || _expectedTimes.isEmpty) return;
    final now = _scoreStopwatch.elapsedMilliseconds / 1000.0;
    final closed = [for (final e in _expectedTimes) if (e <= now - _scoreTolerance) e];
    if (closed.isEmpty) {
      _liveResult = null;
      return;
    }
    _liveResult = score(
      expectedTimes: closed,
      onsetTimes: List.of(_onsetTimes),
      tolerance: _scoreTolerance,
      latencyOffset: _scoreLatency,
    );
  }

  /// 跟弹评分实时条:大字准确率 % + 最近若干下 ✓/←/→/✗ 圆点。评分播放中显在歌词上方。
  Widget _buildScoreStrip(ColorScheme cs) {
    final r = _liveResult;
    final pct = (r == null || r.total == 0) ? null : (r.accuracy * 100).round();
    final verdicts = r?.verdicts ?? const <StrumVerdict>[];
    // 最近 14 下(圆点滚动窗)
    final recent = verdicts.length > 14 ? verdicts.sublist(verdicts.length - 14) : verdicts;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 68,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  pct == null ? '—' : '$pct%',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: cs.primary),
                ),
                Text('准确率', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final v in recent) _verdictDot(v, cs),
                if (recent.isEmpty)
                  Text('跟着 ↓↑ 扫弦,我在听…', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 一个判定圆点:✓ 准(绿)/ ← 早(橙)/ → 晚(橙)/ ✗ 漏(红)。
  Widget _verdictDot(StrumVerdict v, ColorScheme cs) {
    final (color, glyph) = switch (v.judgment) {
      StrumJudgment.onTime => (Colors.green, '✓'),
      StrumJudgment.early => (Colors.orange, '←'),
      StrumJudgment.late => (Colors.orange, '→'),
      StrumJudgment.missed => (cs.error, '✗'),
    };
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        shape: BoxShape.circle,
        border: Border.all(color: color),
      ),
      child: Text(glyph, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.bold)),
    );
  }

  /// 停播总结卡:大字准确率 + 命中明细 + 早晚倾向提示 + 延迟校准滑块(拖动实时重算)。
  /// 「全早 / 全晚」就是延迟没校准好的信号 —— 拖滑块到早晚均衡再存。
  void _showScoreSummary(ScoreResult result) {
    var latency = _scoreLatency;
    var r = result;
    void recompute() {
      r = score(
        expectedTimes: List.of(_expectedTimes),
        onsetTimes: List.of(_onsetTimes),
        tolerance: _scoreTolerance,
        latencyOffset: latency,
      );
    }

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSt) {
            final pct = (r.accuracy * 100).round();
            final ms = r.meanSignedErrorSec * 1000;
            final String hint;
            if (r.total == 0) {
              hint = '没记到该扫的拍子(可能一开播就停了)。';
            } else if (ms < -30) {
              hint = '整体偏早 ${ms.abs().round()}ms → 把延迟调小一点(或你有点抢拍)。';
            } else if (ms > 30) {
              hint = '整体偏晚 ${ms.round()}ms → 把延迟调大一点(或你有点拖拍)。';
            } else {
              hint = '早晚挺均衡 👍';
            }
            return AlertDialog(
              title: const Text('本次跟弹评分'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.total == 0 ? '—' : '$pct%',
                    style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Theme.of(ctx).colorScheme.primary),
                  ),
                  Text(
                    '准确率 · 共 ${r.total} 下(准 ${r.onTime} · 早 ${r.early} · 晚 ${r.late} · 漏 ${r.missed})',
                    style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 6),
                  if (r.hits > 0)
                    Text(
                      '命中的平均误差 ${(r.meanAbsErrorSec * 1000).round()}ms',
                      style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                    ),
                  const SizedBox(height: 10),
                  Text(hint, style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 12),
                  Text('延迟校准 ${(latency * 1000).round()}ms', style: const TextStyle(fontSize: 12)),
                  Slider(
                    min: -0.2,
                    max: 0.2,
                    divisions: 40, // 10ms 一档
                    value: latency,
                    label: '${(latency * 1000).round()}ms',
                    onChanged: (v) => setSt(() {
                      latency = v;
                      recompute();
                    }),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _scoreLatency = latency;
                    _prefs?.setScoreLatency(latency);
                    Navigator.pop(ctx);
                  },
                  child: const Text('保存延迟'),
                ),
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final song = songs[_selected];
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    // 进度条:整曲模式按整首歌走;AB 模式只走 AB 区间那一段(到 B 回 0)。空歌算 0。
    // clamp 防区间外(如 AB 刚设 / 清除瞬间 _idx 还在区间外,progress 会变负或超 1),免得进度条画崩。
    final double progress;
    if (_flat.isEmpty) {
      progress = 0.0;
    } else if (_abActive) {
      final span = _loopLastChord - _loopFirstChord + 1;
      progress = (((_idx - _loopFirstChord) + _slot / (song.beatsPerChord * 2)) / span)
          .clamp(0.0, 1.0);
    } else {
      progress = ((_idx + _slot / (song.beatsPerChord * 2)) / _flat.length)
          .clamp(0.0, 1.0);
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
      // 全屏模式(第58步-6):隐藏顶栏
      appBar: _fullscreen ? null : AppBar(
        // 标题行:选歌下拉框(独占整行宽度,不再和 BPM 抢,就不会重叠出斑马纹)。
        title: DropdownButton<int>(
          value: _selected,
          // 下拉框默认会在选中值下面画一条横线,顶栏里很难看,这里用空部件去掉。
          underline: const SizedBox.shrink(),
          // 让下拉框占满整行宽度:歌名才有地方放,而且下面的 FittedBox 才知道往多窄缩。
          isExpanded: true,
          items: _buildDropdownItems(theme),
          onChanged: (i) {
            if (i == null) return;
            if (i == -1) {
              _openAddSong(); // 点"添加" → 开表单
              return;
            }
            _onSongChanged(i);
          },
          dropdownColor: theme.colorScheme.surface,
          // 下面这个 style 是"下拉框里当前显示的那行歌名"的文字样式。
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
          icon: Icon(Icons.arrow_drop_down, color: theme.colorScheme.onSurface),
        ),
        // 第2行起:图标行 + 筛选芯片 + (搜索框) + 速度信息。
        // (原来这些图标挂在 actions 里和歌名抢宽度,歌名被 FittedBox 缩到看不清;
        //  下移到这第二行后,歌名独占第一行、清晰可读。)
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(_showSearch ? 156 : 120),
          child: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 图标行(原 actions 下移)。横向滚动兜底:窄屏 + 用户歌时图标多也能点到。
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: _buildActionsRow(cs),
                ),
                const SizedBox(height: 2),
                // 筛选芯片:全部 / 英文 / 中文 / 收藏 / 入门 / 初级 / 进阶
                // Wrap:窄屏 7 个芯片自动换行(否则挤一排会溢出)。
                Wrap(
                  spacing: 4,
                  runSpacing: 2,
                  children: [
                    _filterChip(
                      label: '全部',
                      selected: _languageFilter == '全部' && _favoriteFilter == '全部' && _difficultyFilter == null,
                      onTap: () { _setLanguageFilter('全部'); _setFavoriteFilter('全部'); _setDifficultyFilter(null); },
                    ),
                    _filterChip(
                      label: '英文(${songs.where((s) => !RegExp(r'[一-鿿]').hasMatch(s.title)).length})',
                      selected: _languageFilter == '英文',
                      onTap: () { _setFavoriteFilter('全部'); _setLanguageFilter('英文'); },
                    ),
                    _filterChip(
                      label: '中文(${songs.where((s) => RegExp(r'[一-鿿]').hasMatch(s.title)).length})',
                      selected: _languageFilter == '中文',
                      onTap: () { _setFavoriteFilter('全部'); _setLanguageFilter('中文'); },
                    ),
                    _filterChip(
                      label: '收藏(${_favorites.length})',
                      selected: _favoriteFilter == '收藏',
                      onTap: () { _setLanguageFilter('全部'); _setFavoriteFilter('收藏'); },
                    ),
                    _filterChip(
                      label: '入门(${songs.where((s) => difficultyOf(s) == 1).length})',
                      selected: _difficultyFilter == 1,
                      onTap: () => _setDifficultyFilter(_difficultyFilter == 1 ? null : 1),
                    ),
                    _filterChip(
                      label: '初级(${songs.where((s) => difficultyOf(s) == 2).length})',
                      selected: _difficultyFilter == 2,
                      onTap: () => _setDifficultyFilter(_difficultyFilter == 2 ? null : 2),
                    ),
                    _filterChip(
                      label: '进阶(${songs.where((s) => difficultyOf(s) == 3).length})',
                      selected: _difficultyFilter == 3,
                      onTap: () => _setDifficultyFilter(_difficultyFilter == 3 ? null : 3),
                    ),
                  ],
                ),
                // 搜索框(第58步-1):展开时显示在芯片行下面
                if (_showSearch)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: SizedBox(
                      height: 32,
                      child: TextField(
                        controller: _searchCtl,
                        autofocus: true,
                        style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface),
                        decoration: InputDecoration(
                          hintText: '搜索歌名…',
                          hintStyle: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
                          prefixIcon: Icon(Icons.search, size: 18, color: theme.colorScheme.onSurfaceVariant),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? GestureDetector(
                                  onTap: () {
                                    _searchCtl.clear();
                                    _onSearchChanged('');
                                  },
                                  child: Icon(Icons.close, size: 18, color: theme.colorScheme.onSurfaceVariant),
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
                          ),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerHighest,
                        ),
                        onChanged: _onSearchChanged,
                      ),
                    ),
                  ),
                const SizedBox(height: 2),
                // 速度信息
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${_recording ? '🔴 录音中 · ' : ''}${formatTranspose(_transpose)}$_tempo BPM${_tempo == song.tempo ? '' : (_tempo < song.tempo ? ' · 慢练' : ' · 加速')} · ${song.beatsPerChord}拍 · 本次 $_loops / 累计 $_totalLoops 遍 · 练了 ${formatPracticeSec(_totalSec)}${_rampOn && _tempo < song.tempo ? ' · 自动提速→${song.tempo}' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (_monitorOn) _buildPitchMonitor(cs), // 跟唱音准条(完善Step7):monitor 开时显在歌词上方
          if (_scoringSessionActive) _buildScoreStrip(cs), // 跟弹评分实时条(完善Step8)
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
              _prefs?.setPatternIndex(i);
              if (widget.audio.isReady && !_playing) _previewPattern(i);
            },
            abActive: _abActive,
            onClearAb: _clearAb,
            countInNumber: countInNumber,
            nextChord: _flat.isEmpty
                ? '—'
                : (_abActive && _idx >= _loopLastChord
                    ? _flat[_loopFirstChord]
                    : _flat[(_idx + 1) % _flat.length]),
            tempo: _tempo,
            minTempo: (song.tempo / 2).round(),
            maxTempo: (song.tempo * 2).round(),
            onTempoChanged: _setTempo,
            isPlaying: _playing,
            canPlay: widget.audio.isReady,
            onTogglePlay: _togglePlay,
            strumSoundOn: _strumSoundOn,
            onToggleStrumSound: _toggleStrumSound,
            rampOn: _rampOn,
            onToggleRamp: _toggleRamp,
            metronomeSound: widget.audio.metronomeSound,
            metronomeSoundNames: const ['click', 'beep', 'wood', 'rim'],
            onMetronomeSoundChanged: (s) {
              widget.audio.setMetronomeSound(s);
              _prefs?.setMetronomeSound(s);
              setState(() {});
            },
            onChordTap: (c) => widget.audio.playChord(c, semis: _transpose),
            fullscreen: _fullscreen,
            onToggleFullscreen: _toggleFullscreen,
            scoring: _scoring,
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

  /// 顶栏第二行的图标行(原 AppBar actions 下移过来,免得挤歌名)。
  /// 横向滚动兜底:窄屏 + 用户歌(多出编辑/删除)时图标多,滚一下也能点到。
  /// 跟唱音高条(完善Step7):大字音名 + cents 指针条(偏低←绿准区→偏高)。monitor 开时显。
  Widget _buildPitchMonitor(ColorScheme cs) {
    final note = _sungNote;
    final cents = note?.cents ?? 0.0;
    final status = centsStatusLabel(cents); // 准 / 偏低 / 偏高
    final statusColor = status == '准' ? Colors.green : cs.error;
    final label = note == null ? '—' : '${note.name}${note.octave}';
    // cents -50..+50 映射到条上 0..1,再转 Alignment -1..+1(左偏低于中、右偏高于中)。
    final pos = ((cents + 50) / 100).clamp(0.0, 1.0);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: note == null ? cs.onSurfaceVariant : cs.primary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  note == null
                      ? '唱一句试试…(没测到音)'
                      : '$status ${cents > 0 ? '+' : ''}${cents.toStringAsFixed(0)}音分',
                  style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                LayoutBuilder(
                  builder: (ctx, c) => SizedBox(
                    height: 10,
                    child: Stack(
                      children: [
                        // 底条
                        Container(decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(5))),
                        // 中间绿准区(±5 音分)
                        Align(
                          alignment: const Alignment(0, 0),
                          child: Container(
                            width: c.maxWidth * 0.10,
                            decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(5)),
                          ),
                        ),
                        // 指针(随 cents 左右)
                        Align(
                          alignment: Alignment(pos * 2 - 1, 0),
                          child: Container(width: 3, decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(2))),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsRow(ColorScheme cs) {
    final song = songs[_selected];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _actionIcon(
            icon: Icon(_showSearch ? Icons.search_off : Icons.search),
            tooltip: _showSearch ? '关闭搜索' : '搜索歌曲',
            onPressed: _toggleSearch,
          ),
          _actionIcon(
            icon: Icon(_favorites.contains(song.id) ? Icons.favorite : Icons.favorite_border),
            tooltip: _favorites.contains(song.id) ? '取消收藏' : '收藏这首歌',
            onPressed: _toggleFavorite,
            color: _favorites.contains(song.id) ? cs.error : null,
          ),
          if (widget.store.isUserSong(song))
            _actionIcon(
              icon: const Icon(Icons.edit_outlined),
              tooltip: '编辑这首歌',
              onPressed: _openEditSong,
            ),
          if (widget.store.isUserSong(song))
            _actionIcon(
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除这首歌',
              onPressed: _deleteCurrentSong,
            ),
          _actionIcon(
            icon: Icon(_recording ? Icons.stop_circle_outlined : Icons.mic_none_outlined),
            tooltip: _scoring
                ? '评分开着,录音暂不可用(先关评分)'
                : (_recording ? '停止录音' : '录人声(跟唱录音)'),
            onPressed: _scoring ? null : _toggleRecord,
            color: _recording ? cs.error : null,
          ),
          if (_takeWav != null && !_recording)
            _actionIcon(
              icon: const Icon(Icons.replay_rounded),
              tooltip: '听刚才的录音',
              onPressed: _playTake,
            ),
          _actionIcon(
            icon: const Icon(Icons.graphic_eq),
            tooltip: _scoring
                ? '评分开着,音准监测暂不可用(先关评分)'
                : (_monitorOn ? '关音准监测' : '开音准监测(实时看唱的音准)'),
            onPressed: _scoring ? null : _toggleMonitor,
            color: _monitorOn ? cs.primary : null,
          ),
          _actionIcon(
            icon: Icon(_scoring ? Icons.fact_check_rounded : Icons.track_changes_rounded),
            tooltip: _playing
                ? '先暂停再开 / 关 跟弹评分'
                : (_scoring ? '跟弹评分:开 · 听你弹的扫弦逐下打分(点关)' : '跟弹评分:关 · 开麦听扫弦、逐下打分(点开)'),
            onPressed: _playing ? null : _toggleScoring,
            color: _scoring ? cs.primary : null,
          ),
          _actionIcon(
            icon: const Icon(Icons.tune_rounded),
            tooltip: _transpose == 0
                ? '移调(虚拟变调夹)'
                : '移调(虚拟变调夹)· 当前 ${_transpose > 0 ? '+' : ''}$_transpose 半音',
            onPressed: _showTransposeDialog,
            color: _transpose != 0 ? cs.primary : null,
          ),
          _actionIcon(
            icon: const Icon(Icons.format_size_rounded),
            tooltip: '歌词字号',
            onPressed: _showFontScaleDialog,
          ),
        ],
      ),
    );
  }

  /// 图标行里一个紧凑图标(36 触控、shrinkWrap,跟练习栏调速行一个样式)。
  /// color 给了就用它当前景色(收藏/录音红、移调主色);不给走主题默认色。
  /// onPressed 给 null = 置灰禁用(评分开着时给 record/monitor 传 null,它们跟评分共用麦)。
  Widget _actionIcon({
    required Icon icon,
    required String tooltip,
    VoidCallback? onPressed,
    Color? color,
  }) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      icon: icon,
      style: color == null
          ? IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap)
          : IconButton.styleFrom(
              foregroundColor: color, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
    );
  }

  /// 一个语言筛选芯片(第57步):选中时填充主色,未选中用轮廓。
  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? cs.primary : null,
          borderRadius: BorderRadius.circular(12),
          border: selected ? null : Border.all(color: cs.outlineVariant),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: selected ? cs.onPrimary : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
