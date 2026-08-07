// 换和弦训练:挑两个和弦,节拍器按拍响、每 N 拍切到另一个,数你换了多少次。
// 第33步新增的【第5个底导航 tab】——专门练初学者最头疼的"和弦快速切换"。
//
// 复用现成三件套,不另起炉灶:
//   - AudioEngine(构造传入,跟和弦页 / 调音页一样复用 MainScaffold 的共享引擎):
//       playClick(accent:) 每拍嗒一声、当前和弦第 1 拍重音;点卡片换和弦时 playChord 试听一声。
//   - ChordDiagram:画指法图(大图盯着按 + 选择卡上的小图)。
//   - chordShapes:6 个和弦的指法,选和弦就在这几个里循环。
//
// 计时跟 SongScreen 同款思路:Timer.periodic 按 BPM 算出每拍毫秒数循环 tick。
// 这里没用 SongScreen 那套"小节 / 半拍槽位"复杂状态——本页就是一串等宽的拍子,
// 每 _beatsPerChange 拍把 _side 翻面(显示另一个和弦)、_switches +1。
//
// 60 秒挑战:不开无尽模式,跑满 _bpm 拍(= 正好 60 秒:每拍 60/bpm 秒 × bpm 拍 = 60s)自停,
// _switches 就是"一分钟能换几次"的成绩——不用再起一个倒计时定时器。
import 'dart:async';

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
  // 可选和弦列表(按 chordShapes 的插入序:C G Am F D Em)。选和弦就在这 6 个里循环。
  final List<String> _chords = chordShapes.keys.toList();

  String _chordA = 'C'; // 当前选的和弦 A(默认 C)
  String _chordB = 'G'; // 当前选的和弦 B(默认 G——C↔G 是入门最常练的切换)

  int _beatsPerChange = 4; // 每多少拍切到另一个和弦(1 / 2 / 4;4 = 一小节一换,最从容)
  int _bpm = 60; // 节拍器速度。60 BPM = 一秒一拍,跟得上手。
  bool _challenge = false; // 60 秒挑战模式(false = 无尽练到手动停)

  bool _playing = false; // 节拍器在跑吗
  bool _finished = false; // 60 秒挑战跑完了(用来显示成绩;手动停不点亮它)

  int _side = 0; // 当前显示哪个和弦:0=A、1=B
  int _beat = 0; // 当前和弦内数到第几拍了(0.._beatsPerChange-1;0 = 刚切过来,这拍是重音)
  int _switches = 0; // 已经切了几次(每切一次 +1)
  int _elapsedBeats = 0; // 本次跑了多少拍(60 秒挑战用来算倒计时 + 到点自停)

  Timer? _timer;

  AppPreferences? _prefs; // 记住上次选的弦对/速度/档位/挑战(initState 异步读、改时存回)

  /// 当前该显示的和弦名(_side 决定看 A 还是 B)。
  String get _current => _side == 0 ? _chordA : _chordB;

  /// 下一个要换过去的和弦名(就是"另一个")。
  String get _next => _side == 0 ? _chordB : _chordA;

  /// 每拍多少毫秒(60 秒 / BPM)。
  int get _beatMs => (60000 / _bpm).round();

  @override
  void initState() {
    super.initState();
    _loadPrefs(); // 异步读上次的选择;没好之前先用字段默认值(C↔G/60/4/关),不卡首帧
  }

  /// 异步读上次的弦对 / 速度 / 档位 / 挑战开关。SharedPreferences 在测试里 mock 了,getInstance 不会挂。
  /// 和弦名校验还在 chordShapes 里(防以后删和弦导致存的值失效);保证 A≠B;档位校验在 {1,2,4}。
  Future<void> _loadPrefs() async {
    final p = await AppPreferences.load();
    if (!mounted) return; // 异步回来页面可能已经没了
    final chords = chordShapes.keys.toSet();
    setState(() {
      _prefs = p;
      final a = p.getTrainerChordA(_chordA);
      _chordA = chords.contains(a) ? a : _chordA;
      final b = p.getTrainerChordB(_chordB);
      // 存的 B 失效或跟 A 撞了 → 退一个跟 A 不同的默认(A 是 G 就退 C,否则退 G)。
      _chordB = (chords.contains(b) && b != _chordA) ? b : (_chordA == 'G' ? 'C' : 'G');
      final bpc = p.getTrainerBeats(_beatsPerChange);
      _beatsPerChange = const {1, 2, 4}.contains(bpc) ? bpc : _beatsPerChange;
      _bpm = p.getTrainerBpm(_bpm);
      _challenge = p.getTrainerChallenge(_challenge);
    });
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

  /// 开始:重置计数 + 起定时器。引擎没就绪(测试 / 原生库没装)直接 return,不点亮声音路径。
  void _start() {
    if (!widget.audio.isReady) return;
    setState(() {
      _playing = true;
      _finished = false;
      _side = 0; // 从和弦 A 起跑
      _beat = 0;
      _switches = 0;
      _elapsedBeats = 0;
    });
    _timer = Timer.periodic(Duration(milliseconds: _beatMs), (_) => _tick());
  }

  /// 停止:取消定时器、翻 _playing。保留 _switches(让用户看到自己的成绩);不点亮 _finished。
  /// MainScaffold 切走本 tab 时也调它(停掉后台嗒声,跟调音页切走停麦一个道理)。
  void stop() {
    _timer?.cancel();
    _timer = null;
    if (_playing) setState(() => _playing = false);
  }

  /// 每拍回调:嗒一声、推进节拍计数、到点切和弦;60 秒挑战跑满自停。
  void _tick() {
    widget.audio.playClick(accent: _beat == 0); // 当前和弦的第 1 拍 → 重音嗒
    setState(() {
      _elapsedBeats++;
      _beat++;
      if (_beat >= _beatsPerChange) {
        // 这和弦的拍数数满了 → 切到另一个、换和弦计数 +1、节拍归零(下一拍又是新和弦的重音)
        _beat = 0;
        _side = 1 - _side;
        _switches++;
      }
      if (_challenge && _elapsedBeats >= _bpm) {
        // 60 秒挑战:跑满 _bpm 拍 = 正好 60 秒 → 自停、点亮 _finished 显成绩。
        _playing = false;
        _finished = true;
        _timer?.cancel();
        _timer = null;
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

  /// 点和弦卡 → 循环到下一个和弦,跳过跟另一个重复的(保证 A≠B,不然没东西可换)。
  void _cycleChord(bool isA) {
    setState(() {
      final other = isA ? _chordB : _chordA;
      final cur = isA ? _chordA : _chordB;
      var i = _chords.indexOf(cur);
      String next;
      do {
        i = (i + 1) % _chords.length;
        next = _chords[i];
      } while (next == other);
      if (isA) {
        _chordA = next;
      } else {
        _chordB = next;
      }
    });
    // 改了就存:两个都存(简单;另一个没变存回原值无副作用),下次进 tab 直接是这次的配置。
    _prefs?.setTrainerChordA(_chordA);
    _prefs?.setTrainerChordB(_chordB);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('换和弦训练')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '挑两个和弦,跟着嗒声按时切换。点下面的卡片换和弦。',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),

            // —— 选和弦区:两张卡并排(点整张卡循环换和弦 + 试听一声)——
            Row(
              children: [
                Expanded(child: _buildPickerCard(true, '和弦 A', _chordA)),
                const SizedBox(width: 12),
                Expanded(child: _buildPickerCard(false, '和弦 B', _chordB)),
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

  /// 一张和弦选择卡:标签 + 和弦名 + 小指法图 + "换"提示。点整张 → 循环换和弦 + 试听。
  Widget _buildPickerCard(bool isA, String label, String name) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () {
        _cycleChord(isA);
        widget.audio.playChord(name); // 换完听一声,确认选的是哪个
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            const SizedBox(height: 2),
            Text(
              name,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: cs.primary),
            ),
            const SizedBox(height: 4),
            ChordDiagram(frets: chordShapes[name]!, scale: 1.0),
            const SizedBox(height: 2),
            Text('👆 换', style: TextStyle(fontSize: 11, color: cs.outline)),
          ],
        ),
      ),
    );
  }

  /// 当前和弦大显示:超大和弦名 + 大指法图,底下小字提示下一个换到哪个 / 时间到。
  Widget _buildCurrentDisplay(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            _current,
            style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: cs.onPrimaryContainer),
          ),
          const SizedBox(height: 6),
          ChordDiagram(frets: chordShapes[_current]!, scale: 2.2),
          const SizedBox(height: 10),
          if (_finished)
            Text('⏰ 时间到!', style: TextStyle(fontSize: 16, color: cs.onPrimaryContainer))
          else if (_playing)
            Text('下一个 →  $_next', style: TextStyle(fontSize: 14, color: cs.onPrimaryContainer))
          else
            Text(
              '按「开始」,跟着重音(第 1 拍)按时切换',
              style: TextStyle(fontSize: 13, color: cs.onPrimaryContainer),
            ),
        ],
      ),
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
                    value: (_elapsedBeats / _bpm).clamp(0.0, 1.0),
                  ),
                ),
                const SizedBox(width: 8),
                // 还剩几秒:(_bpm - _elapsedBeats) 拍 × 每拍秒数(60 / _bpm)。
                Text('${((_bpm - _elapsedBeats) * 60 / _bpm).ceil()} s'),
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
