// 换和弦训练:挑一串和弦(≥2 个),节拍器按拍响、每 N 拍切到下一个,数你换了多少次。
// 第33步新增的【第5个底导航 tab】——专门练初学者最头疼的"和弦快速切换"。
// 新功能Step16:从"两个和弦 A↔B 翻面"推广成"和弦序列 + 下标前进"——两和弦就是长度 2
// 的序列,老行为是特例;新增经典进行预设一键选、顺序循环 / 随机蹦两种切换方式。
//
// 复用现成三件套,不另起炉灶:
//   - AudioEngine(构造传入,跟和弦页 / 调音页一样复用 MainScaffold 的共享引擎):
//       playClick(accent:) 每拍嗒一声;点卡片/芯片换和弦时 playChord 试听一声;
//       示范音开(新功能Step15)时每个和弦第 1 拍 playChord 播当前和弦代替重音嗒。
//   - ChordDiagram:画指法图(练习区大图盯着按)。
//   - chordShapes:43 个和弦的指法,选和弦都在这些里。
//
// 计时跟 SongScreen 同款思路:Timer.periodic 按 BPM 算出每拍毫秒数循环 tick。
// 这里没用 SongScreen 那套"小节 / 半拍槽位"复杂状态——本页就是一串等宽的拍子,
// 每 _beatsPerChange 拍用 nextTrainerIndex 算出下一个下标(顺序转圈 / 随机蹦)、_switches +1。
//
// 序列不变量(全页地基):线性相邻的两个和弦必须不同——否则"切换"变成没换
// (计数虚加、AnimatedSwitcher 的 ValueKey(_current) 同 key 不动画)。编辑(_cycleAt 跳邻居)、
// 删除(_deleteAt 拒绝破坏)、载入(sanitizeTrainerChords 清洗)三处共同守住,注释互引。
// 序列里允许同一和弦出现多次(卡农里 C 有两次),只有"相邻"不许重复。
//
// 60 秒挑战:不开无尽模式,跑满 _bpm 拍(= 正好 60 秒:每拍 60/bpm 秒 × bpm 拍 = 60s)自停,
// _switches 就是"一分钟能换几次"的成绩——不用再起一个倒计时定时器。
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../audio/audio_engine.dart';
import '../models.dart';
import '../prefs/app_preferences.dart';
import '../widgets/chord_diagram.dart';

/// 换和弦训练页。[audio] 复用 MainScaffold 的共享引擎(不二次 init,跟和弦页 / 调音页一样)。
class ChordTrainerScreen extends StatefulWidget {
  final AudioEngine audio;

  const ChordTrainerScreen({required this.audio, super.key});

  @override
  State<ChordTrainerScreen> createState() => ChordTrainerState();
}

class ChordTrainerState extends State<ChordTrainerScreen> {
  // 全和弦池(按 chordShapes 插入序,第58步-7难度分级用)。
  final List<String> _allChords = chordShapes.keys.toList();

  // —— 难度分级(第58步-7) ——
  // beginner: C G Am F (4个核心)
  // easy: C G Am F D Em Dm A (8个常用)
  // medium: 所有大三+小三 (14个)
  // hard: 全部43个
  // custom: 自选两个(默认,保持旧行为)
  static const _difficultyPools = {
    'beginner': ['C', 'G', 'Am', 'F'],
    'easy': ['C', 'G', 'Am', 'F', 'D', 'Em', 'Dm', 'A'],
  };
  String _difficulty = 'custom'; // 默认自定义(跟旧版一样)

  /// 当前难度下的可选和弦(第58步-7)。
  List<String> _poolForDifficulty(String d) {
    if (d == 'medium') {
      return ['C','D','F','G','A','Bb','E','Am','Bm','Cm','Dm','Em','Fm','Gm'];
    }
    if (d == 'hard') return _allChords;
    return _difficultyPools[d] ?? _allChords;
  }

  List<String> get _pool => _poolForDifficulty(_difficulty);

  /// 从当前难度池随机抽两个不同和弦(老版行为,新功能Step16 起等价于"重置成长度 2 的序列")。
  /// 随机抽两个不同的和弦。用 dart:math Random 真随机(旧版用时间戳模 pool.length 有强偏置:
  /// 入门档永远只抽相邻和弦对)。想要更多和弦 → 用预设一键选 / + 号自己加(不猜用户想要几个,保持简单)。
  void _randomPick() {
    final pool = _pool;
    if (pool.length < 2) return;
    final a = pool[_rnd.nextInt(pool.length)];
    var b = a;
    while (b == a) {
      b = pool[_rnd.nextInt(pool.length)];
    }
    setState(() {
      _chords = [a, b];
      _idx = 0;
    });
    _saveChords();
    widget.audio.playChord(a);
  }

  /// 切难度(第58步-7 / 新功能Step16 改过滤保序):序列里不在新池的和弦被滤掉、
  /// 剩下的保序留下(如卡农 8 个切到入门档 → 自动留成 C-G-Am-F-C-F-G 7 个),
  /// 比"作废重抽"友好;清完不足 2 个才随机抽一组。
  void _setDifficulty(String d) {
    if (d == _difficulty) return;
    setState(() => _difficulty = d);
    _prefs?.setTrainerDifficulty(d);
    final pool = _pool;
    final filtered = sanitizeTrainerChords(_chords.where(pool.contains).toList());
    if (filtered.length < 2) {
      _randomPick();
    } else {
      setState(() {
        _chords = filtered;
        _idx = _idx.clamp(0, _chords.length - 1); // 序列变短了,下标收回界内
      });
      _saveChords();
    }
  }

  /// 当前难度下的最佳成绩(第58步-7)。
  int get _bestScore =>
      _difficulty == 'custom' ? 0 : (_prefs?.getTrainerBest(_difficulty) ?? 0);

  // 和弦序列(新功能Step16):≥2 个、线性相邻不重复(见文件头"序列不变量")。
  // 老版的 A/B 就是前两个元素,老用户偏好迁移过来无缝。
  List<String> _chords = ['C', 'G'];
  int _idx = 0; // 当前练到序列里第几个(老版 _side 的推广:长度 2 时就是 0/1 翻面)
  String _mode = 'sequence'; // 切换方式:'sequence' 顺序循环 / 'random' 随机蹦
  final Random _rnd = Random(); // 随机模式用(字段级复用一个,不每拍 new)

  int _beatsPerChange = 4; // 每多少拍切到另一个和弦(1 / 2 / 4;4 = 一小节一换,最从容)
  int _bpm = 60; // 节拍器速度。60 BPM = 一秒一拍,跟得上手。
  bool _challenge = false; // 60 秒挑战模式(false = 无尽练到手动停)
  bool _chordSoundOn = true; // 示范音(新功能Step15):开 = 每次换到新和弦的第 1 拍播一声该和弦

  bool _playing = false; // 节拍器在跑吗
  bool _finished = false; // 60 秒挑战跑完了(用来显示成绩;手动停不点亮它)

  int _beat = 0; // 当前和弦内数到第几拍了(0.._beatsPerChange-1;0 = 刚切过来,这拍是重音)
  int _switches = 0; // 已经切了几次(每切一次 +1)
  int _elapsedBeats = 0; // 本次跑了多少拍(60 秒挑战用来算倒计时 + 到点自停)
  int _targetBeats = 0; // 60 秒挑战开始时快照的目标拍数(=起跑时的 bpm),中途改 bpm 不影响本次时长

  Timer? _timer;

  AppPreferences? _prefs; // 记住上次选的弦对/速度/档位/挑战(initState 异步读、改时存回)

  /// 当前该显示的和弦名(序列里 _idx 处)。
  String get _current => _chords[_idx];

  /// 下一个要换过去的和弦名。顺序模式提前知道(转圈的下一个);
  /// 随机模式返回 null——下一个在切的那一瞬间才决定,提前不知道,这正是随机模式的训练点。
  /// 用可空类型(而不是返回 '?')让编译器逼着每个消费点按模式分支。
  String? get _next =>
      _mode == 'sequence' ? _chords[(_idx + 1) % _chords.length] : null;

  /// 每拍多少毫秒(60 秒 / BPM)。
  int get _beatMs => (60000 / _bpm).round();

  @override
  void initState() {
    super.initState();
    _loadPrefs(); // 异步读上次的选择;没好之前先用字段默认值(C↔G/60/4/关),不卡首帧
  }

  /// 异步读上次的选择(序列 / 模式 / 速度 / 档位 / 挑战 / 示范音)。SharedPreferences 在测试里 mock 了,getInstance 不会挂。
  Future<void> _loadPrefs() async {
    final p = await AppPreferences.load();
    if (!mounted) return; // 异步回来页面可能已经没了
    setState(() {
      _prefs = p;
      // 序列三层 fallback(新功能Step16):新键存过且清洗后仍有效 → 用;
      // 否则 → 老用户的老键 chord_a/chord_b 迁移(一次性,老键只读不删,降级兼容);
      // 都没有 → 字段默认 [C, G]。
      final saved = p.getTrainerChords();
      if (saved != null) {
        final clean = sanitizeTrainerChords(saved.toList()); // getStringList 可能返回不可变列表,先拷贝
        if (clean.isNotEmpty) _chords = clean;
      } else {
        _chords = _migrateLegacyPair(p);
      }
      final m = p.getTrainerMode('sequence');
      _mode = (m == 'sequence' || m == 'random') ? m : 'sequence';
      final bpc = p.getTrainerBeats(_beatsPerChange);
      _beatsPerChange = const {1, 2, 4}.contains(bpc) ? bpc : _beatsPerChange;
      _bpm = p.getTrainerBpm(_bpm);
      _challenge = p.getTrainerChallenge(_challenge);
      _chordSoundOn = p.getTrainerChordSound(true);
      final savedDiff = p.getTrainerDifficulty('custom');
      _difficulty = (savedDiff == 'beginner' || savedDiff == 'easy' || savedDiff == 'medium' || savedDiff == 'hard' || savedDiff == 'custom') ? savedDiff : 'custom';
    });
  }

  /// 老版双和弦偏好 → 长度 2 的序列(新功能Step16 迁移)。
  /// 校验跟老版一致:a 不在 chordShapes → 默认 C;b 失效或 == a → 退一个跟 a 不同的默认。
  List<String> _migrateLegacyPair(AppPreferences p) {
    final chords = chordShapes.keys.toSet();
    final a = chords.contains(p.getTrainerChordA('C')) ? p.getTrainerChordA('C') : 'C';
    final rawB = p.getTrainerChordB('G');
    final b = (chords.contains(rawB) && rawB != a) ? rawB : (a == 'G' ? 'C' : 'G');
    return [a, b];
  }

  @override
  void dispose() {
    _timer?.cancel(); // 离开页清掉定时器,别让嗒声在后台继续响
    super.dispose();
  }

  /// 开始 / 停止(点开始按钮)。
  void _toggle() {
    if (_playing) {
      stop();
    } else {
      _start();
    }
  }

  /// 切"示范音"开关(新功能Step15)。播放中切也立刻生效(下一拍就按新状态响)。同时存下来。
  void _toggleChordSound() {
    setState(() => _chordSoundOn = !_chordSoundOn);
    _prefs?.setTrainerChordSound(_chordSoundOn);
  }

  /// 开始:重置计数 + 起定时器。引擎没就绪(测试 / 原生库没装)直接 return,不点亮声音路径。
  void _start() {
    if (!widget.audio.isReady) return;
    setState(() {
      _playing = true;
      _finished = false;
      _idx = 0; // 从序列第 1 个起跑(老版 _side = 0)
      _beat = 0;
      _switches = 0;
      _elapsedBeats = 0;
      _targetBeats = _bpm; // 快照起跑时的 bpm,中途改 bpm 不再影响本次挑战时长
    });
    _timer = Timer.periodic(Duration(milliseconds: _beatMs), (_) => _tick());
  }

  /// 停止:取消定时器、翻 _playing。保留 _switches(让用户看到自己的成绩);不点亮 _finished。
  void stop() {
    _timer?.cancel();
    _timer = null;
    if (_playing) setState(() => _playing = false);
  }

  /// 每拍回调:响声、推进节拍计数、到点切和弦;60 秒挑战跑满自停。
  void _tick() {
    // 示范音(新功能Step15)开:每个和弦的第 1 拍播一声当前和弦的扫弦,代替重音嗒——
    // 扫弦起音本身就是重音(跟弹唱页"扫弦声开代替嗒声"一个套路),新手能对照听换的指法对不对。
    // 切换发生在上一拍末尾,所以 _beat==0 的这拍 _current 已是新和弦,时序天然对。
    // 关:全嗒声(老行为)。每 1 拍换时每拍都是第 1 拍 → 每拍都是和弦声,自然。
    if (_chordSoundOn && _beat == 0) {
      widget.audio.playChord(_current);
    } else {
      widget.audio.playClick(accent: _beat == 0); // 当前和弦的第 1 拍 → 重音嗒
    }
    setState(() {
      _elapsedBeats++;
      _beat++;
      if (_beat >= _beatsPerChange) {
        // 这和弦的拍数数满了 → 切到下一个(顺序转圈 / 随机蹦,纯函数算)、换和弦计数 +1、
        // 节拍归零(下一拍又是新和弦的重音)。相邻不重复不变量保证"切了就是真换了"。
        _beat = 0;
        _idx = nextTrainerIndex(_chords.length, _idx, random: _mode == 'random', rnd: _rnd);
        _switches++;
      }
      if (_challenge && _elapsedBeats >= _targetBeats) {
        // 60 秒挑战:跑满快照的目标拍数(起跑 bpm 决定,每拍 60000/bpm ms × bpm 拍 = 60s) → 自停。
        _playing = false;
        _finished = true;
        _timer?.cancel();
        _timer = null;
        // 第58步-7:更新最佳成绩
        if (_switches > _bestScore && _difficulty != 'custom') {
          _prefs?.setTrainerBest(_difficulty, _switches);
        }
      }
    });
  }

  /// 改 BPM:记下新值;跑着就重启定时器用新间隔(跟 SongScreen 调速重启定时器一个套路)。
  void _setBpm(double v) {
    final n = v.round();
    if (n == _bpm) return;
    setState(() => _bpm = n);
    _prefs?.setTrainerBpm(n);
    if (_playing) {
      _timer?.cancel();
      _timer = Timer.periodic(Duration(milliseconds: _beatMs), (_) => _tick());
    }
  }

  /// 改"每几拍换":记下新值、当前和弦节拍归零(按新节拍从头数)。
  void _setBeatsPerChange(int v) {
    if (v == _beatsPerChange) return;
    setState(() {
      _beatsPerChange = v;
      _beat = 0;
    });
    _prefs?.setTrainerBeats(v);
  }

  /// 点序列里的和弦 chip → 在当前难度池里循环到下一个(老版 _cycleChord 的推广),
  /// 跳过左右邻居的值——保住"线性相邻不重复"不变量(见文件头),切了才是真换了。
  /// 返回切换后的和弦名(直接能放给 playChord 试听)。
  String _cycleAt(int i) {
    final left = i > 0 ? _chords[i - 1] : null; // 左邻居;序列首没有左邻居
    final right = i < _chords.length - 1 ? _chords[i + 1] : null; // 右邻居
    final pool = _pool;
    var k = pool.indexOf(_chords[i]);
    if (k < 0) k = 0;
    String next;
    do {
      k = (k + 1) % pool.length;
      next = pool[k];
    } while (next == left || next == right);
    setState(() => _chords[i] = next);
    _saveChords();
    return next;
  }

  /// 删序列里第 i 个和弦(新功能Step16)。宁可不让删,也不产生"切了等于没切"的序列:
  /// 删完会造成新的相邻重复(如 C-G-C 删中间的 G)或长度 < 2 → 拒绝(返回 false,chip 的 × 不该亮)。
  bool _deleteAt(int i) {
    if (_chords.length <= 2) return false; // 至少留 2 个,不然没东西可换
    final left = i > 0 ? _chords[i - 1] : null;
    final right = i < _chords.length - 1 ? _chords[i + 1] : null;
    if (left != null && right != null && left == right) return false; // 删了左右就贴上,重复了
    setState(() {
      _chords.removeAt(i);
      _idx = _idx.clamp(0, _chords.length - 1); // 序列变短,下标收回界内
    });
    _saveChords();
    return true;
  }

  /// 末尾追加一个和弦(新功能Step16 的 + 号)。跟末尾元素相同的不让加(相邻重复);
  /// 首尾环绕的洞([C,...,F,C] 转回开头那下多按一拍同和弦)不拦——拦了卡农这种合法序列都拼不出来。
  void _append(String chord) {
    if (chord == _chords.last) return;
    setState(() => _chords.add(chord));
    _saveChords();
  }

  /// 一键套用经典进行预设(新功能Step16)。进行是有序的 → 预设天然顺序模式
  /// (套完再手动切随机也行);从第 1 个起、试听一声。
  void _applyPreset(TrainerPreset p) {
    setState(() {
      _chords = [...p.chords];
      _idx = 0;
      _mode = 'sequence';
    });
    _saveChords();
    _prefs?.setTrainerMode('sequence');
    widget.audio.playChord(p.chords.first);
  }

  /// 切换方式(新功能Step16):sequence 顺序循环 / random 随机蹦。播放中切也直接生效
  /// (下一个"换"就按新模式选目标;正在响的这段不受影响)。
  void _setMode(String m) {
    if (m == _mode) return;
    setState(() => _mode = m);
    _prefs?.setTrainerMode(m);
  }

  /// 存当前序列(编辑 / 迁移 / 难度过滤后都走这里,老键不再写——迁移是一次性的)。
  void _saveChords() => _prefs?.setTrainerChords(List.of(_chords));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('换和弦训练'),
        // 示范音开关(新功能Step15):跟琶音/指弹/弹唱页同款小图标。
        actions: [
          IconButton(
            onPressed: _toggleChordSound,
            tooltip: _chordSoundOn ? '示范音:开(换和弦时听一声)' : '示范音:关(只听节拍器)',
            icon: Icon(_chordSoundOn ? Icons.graphic_eq : Icons.volume_off),
            style: IconButton.styleFrom(
              foregroundColor: _chordSoundOn ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '挑几个和弦,跟着节拍按时切换。可以选经典进行,也可以自己组。',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),

            // —— 难度分级 + 随机抽(第58步-7)——
            const Text('难度'),
            Wrap(
              spacing: 6,
              children: [
                for (final e in const [
                  ('custom', '自定义'),
                  ('beginner', '入门(4)'),
                  ('easy', '初级(8)'),
                  ('medium', '中级(14)'),
                  ('hard', '高级(43)'),
                ])
                  ChoiceChip(
                    label: Text(e.$2, style: const TextStyle(fontSize: 11)),
                    selected: _difficulty == e.$1,
                    onSelected: (_) => _setDifficulty(e.$1),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            if (_bestScore > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '🏆 最佳: $_bestScore 次/分',
                  style: TextStyle(fontSize: 12, color: cs.primary, fontWeight: FontWeight.w600),
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 36,
              child: OutlinedButton.icon(
                onPressed: _randomPick,
                icon: const Icon(Icons.shuffle, size: 18),
                label: const Text('随机抽一组'),
              ),
            ),
            const SizedBox(height: 12),

            // —— 经典进行预设(新功能Step16):一次性动作用 ActionChip(不是选中态,不用 ChoiceChip)——
            const Text('经典进行(一键选)'),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final p in trainerPresets)
                  ActionChip(
                    label: Text(p.name, style: const TextStyle(fontSize: 11)),
                    tooltip: p.hint,
                    onPressed: () => _applyPreset(p),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // —— 切换方式(新功能Step16)——
            const Text('切换方式'),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('顺序循环', style: TextStyle(fontSize: 11)),
                  selected: _mode == 'sequence',
                  onSelected: (_) => _setMode('sequence'),
                  visualDensity: VisualDensity.compact,
                ),
                ChoiceChip(
                  label: const Text('随机蹦', style: TextStyle(fontSize: 11)),
                  selected: _mode == 'random',
                  onSelected: (_) => _setMode('random'),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            Text(
              _mode == 'sequence' ? '照序列转圈,下一个提前知道' : '从组里随机蹦下一个,练"看到和弦名立刻反应"',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),

            // —— 和弦序列编辑区(新功能Step16,替换老版两张卡):点 chip 循环换 + 试听,× 删,+ 加 ——
            // chip 上不放小指法图:N 个图放不下;练习大显示区有当前和弦的图、点选即试听,信息不丢。
            const Text('和弦序列(点换和弦,× 删,至少留 2 个)'),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (var i = 0; i < _chords.length; i++)
                  InputChip(
                    label: Text(
                      _chords[i],
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        // 正在练的那个高亮一点,编辑时心里有数(纯视觉,不影响逻辑)
                        color: _playing && i == _idx ? cs.primary : cs.onSurface,
                      ),
                    ),
                    onPressed: () {
                      final next = _cycleAt(i);
                      widget.audio.playChord(next); // 换完听一声,确认选的是新和弦
                    },
                    onDeleted: _chords.length > 2 ? () => _deleteAt(i) : null, // 只剩 2 个不给删
                    deleteIconColor: cs.onSurfaceVariant,
                    visualDensity: VisualDensity.compact,
                  ),
                InputChip(
                  label: const Text('+', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  tooltip: '加一个和弦',
                  onPressed: _showAddSheet,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),

            // —— 设置区(开始前调好)——
            Text('设置', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),

            // BPM 滑块
            Row(
              children: [
                const Text('速度'),
                Expanded(
                  child: Slider(
                    min: 40,
                    max: 120,
                    divisions: 80, // 40~120 一格 1 BPM
                    value: _bpm.toDouble(),
                    label: '$_bpm BPM',
                    onChanged: _setBpm,
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: Text('$_bpm', textAlign: TextAlign.end),
                ),
              ],
            ),

            // 每几拍换:1 / 2 / 4 三档
            const Text('每多少拍换一次'),
            Wrap(
              spacing: 8,
              children: [1, 2, 4]
                  .map(
                    (v) => ChoiceChip(
                      label: Text('$v 拍'),
                      selected: _beatsPerChange == v,
                      onSelected: (_) => _setBeatsPerChange(v),
                    ),
                  )
                  .toList(),
            ),

            // 60 秒挑战开关(跑着时不让切,免得改了目标)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('60 秒挑战'),
              subtitle: const Text('数一分钟能干净换几次'),
              value: _challenge,
              onChanged: _playing
                  ? null
                  : (v) {
                      setState(() => _challenge = v);
                      _prefs?.setTrainerChallenge(v);
                    },
            ),

            const SizedBox(height: 12),

            // —— 练习区:当前和弦大显示 + 计数 + 开始按钮(练习时盯这里)——
            _buildCurrentDisplay(cs),
            const SizedBox(height: 12),
            _buildCounter(cs),
            const SizedBox(height: 12),
            _buildStartButton(cs),
          ],
        ),
      ),
    );
  }

  /// 加和弦面板(新功能Step16):当前难度池的和弦 chip 一屏挑,点一个 → 追加 + 试听,
  /// 面板不关可连续加(hard 档 43 个也在 sheet 里滚得动)。跟末尾相同的置灰(加了等于没加)。
  void _showAddSheet() {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('加一个和弦(可连续加)', style: Theme.of(sheetCtx).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                '从当前难度池里挑;跟序列末尾相同的不让加',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final c in _pool)
                    InputChip(
                      label: Text(c, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      onPressed: c == _chords.last ? null : () => _append(c),
                      tooltip: c == _chords.last ? '跟末尾相同,加了等于没加' : '加到序列末尾',
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 当前和弦大显示:超大和弦名 + 大指法图,底下进行点行 + 小字提示下一个 / 时间到。
  /// 第55步:用 AnimatedSwitcher 缩放动画,切换和弦时不突兀——依赖"相邻不重复"不变量
  /// (同 key 不动画),载入/编辑/删除三处守的就是它。
  Widget _buildCurrentDisplay(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, animation) =>
                ScaleTransition(scale: animation, child: child),
            child: Text(
              _current,
              key: ValueKey(_current),
              style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: cs.onPrimaryContainer),
            ),
          ),
          const SizedBox(height: 6),
          ChordDiagram(frets: chordShapes[_current]!, scale: 2.2),
          const SizedBox(height: 10),
          // 进行点行(新功能Step16,照琶音页 _buildChordDots 的样子):C > G > Am > F,
          // 当前项大号主色。只 2 个和弦时不显示(来回两个点没信息量);随机模式不显示
          // (下一个未知,画出来反而误导——练的就是不预瞄)。
          if (_mode == 'sequence' && _chords.length > 2)
            DefaultTextStyle(
              style: TextStyle(color: cs.onPrimaryContainer),
              child: _buildSequenceDots(cs),
            ),
          const SizedBox(height: 6),
          if (_finished)
            Text('⏰ 时间到!', style: TextStyle(fontSize: 16, color: cs.onPrimaryContainer))
          else if (_playing)
            Text(
              // 顺序:下一个提前知道;随机:下一个在切那瞬间才决定(训练点)。
              _next != null ? '下一个 →  $_next' : '下一个 →  ?(随机蹦)',
              style: TextStyle(fontSize: 14, color: cs.onPrimaryContainer),
            )
          else
            Text(
              '按「开始」,跟着重音(第 1 拍)按时切换',
              style: TextStyle(fontSize: 13, color: cs.onPrimaryContainer),
            ),
        ],
      ),
    );
  }

  /// 序列进行点:C > G > Am > F,当前项放大高亮、其余淡。FittedBox 兜底:卡农 8 个也塞得下。
  Widget _buildSequenceDots(ColorScheme cs) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var i = 0; i < _chords.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.chevron_right_rounded, size: 14, color: cs.onPrimaryContainer.withValues(alpha: 0.5)),
            ),
          Text(
            _chords[i],
            style: TextStyle(
              fontSize: i == _idx ? 18 : 13,
              fontWeight: FontWeight.bold,
              color: i == _idx ? cs.primary : cs.onPrimaryContainer.withValues(alpha: 0.55),
            ),
          ),
        ],
      ]),
    );
  }

  /// 计数 + (60 秒挑战时)倒计时进度条 / 成绩。
  Widget _buildCounter(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('已换', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        Text(
          '$_switches 次',
          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
        ),
        if (_challenge && _playing)
          // 倒计时:已跑 _elapsedBeats 拍 / 总 _bpm 拍(= 60 秒)。
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: _targetBeats > 0
                        ? (_elapsedBeats / _targetBeats).clamp(0.0, 1.0)
                        : 0.0,
                  ),
                ),
                const SizedBox(width: 8),
                // 还剩几秒:用快照的目标拍数算(起跑 bpm 决定),中途改 bpm 不让倒计时跳。
                Text('${((_targetBeats - _elapsedBeats) * 60 / _targetBeats).ceil()} s'),
              ],
            ),
          ),
        if (_challenge && _finished)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '✅ 一分钟换了 $_switches 次',
              style: TextStyle(fontSize: 15, color: cs.primary, fontWeight: FontWeight.bold),
            ),
          ),
      ],
    );
  }

  /// 开始 / 停止按钮。引擎没就绪时禁用(灰掉、点了不出声,跟练习页 ▶ 一样)。
  Widget _buildStartButton(ColorScheme cs) {
    final ready = widget.audio.isReady;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        onPressed: ready ? _toggle : null,
        icon: Icon(_playing ? Icons.stop : Icons.play_arrow),
        label: Text(_playing ? '停止' : '开始'),
      ),
    );
  }
}
