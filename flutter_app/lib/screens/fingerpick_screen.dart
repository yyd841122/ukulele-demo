// 指弹页(第69步/第75步/第78步/第79步)。
// 单一模式:真实指弹曲谱跟练(小星星/两只老虎/欢乐颂/卡农/绿袖子/千与千寻)。
// 开示范音 = 听曲谱;关示范音 = 跟练(只剩节拍器嗒声 + 高亮,自己弹)。
//
// 第78步核心修复:节奏推进改成 tick 累积——每个 16 分 tick 累加 _ticksHeld,
// 达到当前音的 duration 才推进到下一个音。这样四分音符(duration=4)真的占 4 个 tick = 1 拍。
// (旧 bug: _globalSlot += duration,相邻音只隔 1 tick,节奏快了 N 倍)
//
// 第79步:① 加入门儿歌并前置小星星;② 曲谱模式播放时每拍嗒一声节拍器(跟练);
// ③ 删掉原来的「练习」子模式(拿和弦歌练指弹型、和曲谱无关、容易混)——指弹 tab 现在只练曲子。
import 'dart:async';

import 'package:flutter/material.dart';

import '../audio/audio_engine.dart';
import '../models.dart';
import '../prefs/app_preferences.dart';
import '../widgets/fretboard_view.dart';

class FingerpickScreen extends StatefulWidget {
  final AudioEngine audio;

  const FingerpickScreen({required this.audio, super.key});

  @override
  State<FingerpickScreen> createState() => FingerpickScreenState();
}

class FingerpickScreenState extends State<FingerpickScreen> {
  // 持久化:记住上次的曲谱 / 示范音 / 速度(跨重启)。initState 异步加载,读好再 reconcile。
  AppPreferences? _prefs;
  int _selectedScore = 0;

  // 播放状态
  bool _playing = false;
  bool _soundOn = true;          // 示范音:开=听曲谱(播旋律);关=跟练(只剩节拍器+高亮)
  int _tempo = 85;
  Timer? _timer;
  bool _inCountIn = false;       // 预备拍阶段
  bool _everPlayed = false;      // 这首歌正式播过(用来决定是否再数预备拍)
  int _countInSlot = 0;          // 预备拍已走的 16 分 tick(0..15)
  bool _pendingStart = false;    // 预备拍刚结束,下一 tick 播第一个音(修过渡早1tick)

  // —— 曲谱数据(换歌时重建)——
  List<FingerpickSlot> _flatSlots = []; // 拍扁的所有音
  int _globalSlot = 0;           // 当前第几个音(在 _flatSlots 里)
  int _ticksHeld = 0;            // 当前音已持续多少个 16 分 tick
  int _scorePlayTicks = 0;       // 正式播放起算的绝对 16 分 tick(给跟练节拍器每拍嗒一声用)
  List<int> _barStarts = [];     // 每小节起始 slot 下标(画小节线)
  List<int> _barOfSlot = [];     // 每个 slot 属于第几小节

  /// 一个 16 分音符 tick 的时长。
  Duration get _tickDuration => Duration(milliseconds: (15000 / _tempo).round());

  @override
  void initState() {
    super.initState();
    _rebuildScoreSlots();
    _loadPrefs(); // 异步读上次的曲谱/示范音/速度,读好再 reconcile(不卡首帧:先用默认值画)
  }

  Future<void> _loadPrefs() async {
    final p = await AppPreferences.load();
    if (!mounted || builtinFingerpickSongs.isEmpty) return;
    setState(() {
      _prefs = p;
      _selectedScore =
          p.getFingerpickScore(0).clamp(0, builtinFingerpickSongs.length - 1);
      _soundOn = p.getFingerpickSound(true);
      _rebuildScoreSlots(); // 按载入的曲谱重建槽位(_tempo 重设成该曲谱自带速度)
      _tempo = (p.getFingerpickTempo() ?? _tempo).clamp(40, 180); // 存过 → 覆盖
    });
  }

  // —— 曲谱:拍扁 + 建小节映射 ——
  void _rebuildScoreSlots() {
    if (builtinFingerpickSongs.isEmpty) return;
    final fSong = builtinFingerpickSongs[_selectedScore.clamp(0, builtinFingerpickSongs.length - 1)];
    _flatSlots = fSong.flatSlots;
    _tempo = fSong.tempo;
    _barStarts = [];
    _barOfSlot = [];
    var idx = 0;
    for (var b = 0; b < fSong.bars.length; b++) {
      _barStarts.add(idx);
      for (var s = 0; s < fSong.bars[b].slots.length; s++) {
        _barOfSlot.add(b);
        idx++;
      }
    }
    _resetPlayPos();
  }

  void _resetPlayPos() {
    _globalSlot = 0;
    _ticksHeld = 0;
    _scorePlayTicks = 0;
    _inCountIn = false;
    _everPlayed = false;
    _countInSlot = 0;
    _pendingStart = false;
  }

  // —— 播放控制 ——
  void _togglePlay() {
    if (_playing) { _stop(); return; }
    if (!widget.audio.isReady) return;

    if (!_everPlayed) {
      // 第一次:从头 + 数预备拍
      _globalSlot = 0;
      _ticksHeld = 0;
      _inCountIn = true;
      _countInSlot = 0;
    }
    // 否则:暂停后恢复,接着当前位置播(不重数预备拍)
    setState(() => _playing = true);
    _timer = Timer.periodic(_tickDuration, (_) => _onTick());
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    if (_playing) setState(() => _playing = false);
  }

  void _onTick() {
    _tickScore();
    setState(() {});
  }

  /// 每 16 分 tick 一次。预备拍阶段嗒声倒计时;正式阶段按当前音 duration 累积 tick + 每拍节拍器。
  void _tickScore() {
    if (_flatSlots.isEmpty) return;

    if (_inCountIn) {
      // 预备拍 4 拍 = 16 个 16 分 tick。每 4 tick(=1 拍)嗒一声,第 1 拍重音。
      if (_countInSlot % 4 == 0) {
        widget.audio.playClick(accent: _countInSlot == 0);
      }
      _countInSlot++;
      if (_countInSlot >= 16) {
        _inCountIn = false;
        _everPlayed = true;
        _pendingStart = true; // 不立即播 slot0;下一 tick(=整曲 beat1)再播,修"过渡早1拍"
      }
      return;
    }

    // 预备拍刚结束:这一 tick 是整曲第 1 拍的强位,播 slot0 + 重音嗒(给跟练一个明确的"起")。
    if (_pendingStart) {
      _pendingStart = false;
      _globalSlot = 0;
      _ticksHeld = 0;
      _scorePlayTicks = 0;
      _playSlot(0);
      widget.audio.playClick(accent: true); // 整曲第 1 拍重音
      return;
    }

    // 正式:_ticksHeld 累积。达到当前音的 duration 才推进到下一个音。
    _ticksHeld++;
    _scorePlayTicks++;
    // 跟练节拍器(第79步):每 4 个 16 分 tick(=1 拍)嗒一声,每 16 个(=1 小节)打重音。
    // 绑【绝对 tick】、不绑音符时值——节拍器始终稳,正好给"跟练"打拍(关掉示范音就只剩它 + 高亮)。
    if (_scorePlayTicks % 4 == 0) {
      widget.audio.playClick(accent: _scorePlayTicks % 16 == 0);
    }
    final cur = _flatSlots[_globalSlot];
    final dur = cur.duration <= 0 ? 1 : cur.duration;
    if (_ticksHeld >= dur) {
      _ticksHeld = 0;
      // 整曲末尾(最后一个音 → 回第1个)插【过渡拍】:嗒满1小节(4拍)再开下一遍。
      // 复用上面的预备拍机制(含 _pendingStart 首拍对齐),给新手换手时间(完善Step9 加)。
      if (isLastIndex(_globalSlot, _flatSlots.length)) {
        _globalSlot = 0;
        _inCountIn = true;
        _countInSlot = 0;
        return; // 本 tick 不播 slot0;下一 tick 起由上面 if(_inCountIn) 分支嗒4拍
      }
      _globalSlot = (_globalSlot + 1) % _flatSlots.length;
      _playSlot(_globalSlot);
    }
  }

  void _playSlot(int slot) {
    if (slot < 0 || slot >= _flatSlots.length) return;
    final s = _flatSlots[slot];
    if (s.shouldPlay && _soundOn) {
      widget.audio.playPitch(s.stringIndex!, s.fret);
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  // —— UI ——
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: _buildScoreAppBar(cs, theme),
      body: _buildScoreBody(cs, theme),
    );
  }

  PreferredSizeWidget _buildScoreAppBar(ColorScheme cs, ThemeData theme) {
    return AppBar(
      title: DropdownButton<int>(
        value: _selectedScore,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        items: [
          for (var i = 0; i < builtinFingerpickSongs.length; i++)
            DropdownMenuItem(
              value: i,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(builtinFingerpickSongs[i].title, style: theme.textTheme.titleSmall),
                if (builtinFingerpickSongs[i].subtitle.isNotEmpty)
                  Text(builtinFingerpickSongs[i].subtitle, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
              ]),
            ),
        ],
        onChanged: (i) { if (i != null) { _stop(); setState(() { _selectedScore = i; _rebuildScoreSlots(); }); _prefs?.setFingerpickScore(i); _prefs?.setFingerpickTempo(_tempo); } },
        dropdownColor: cs.surface,
        style: theme.textTheme.titleMedium?.copyWith(color: cs.onSurface),
      ),
    );
  }

  Widget _buildScoreBody(ColorScheme cs, ThemeData theme) {
    final fSong = builtinFingerpickSongs.isNotEmpty
        ? builtinFingerpickSongs[_selectedScore.clamp(0, builtinFingerpickSongs.length - 1)]
        : null;
    if (fSong == null) return const Center(child: Text('没有指弹曲谱'));

    final currentBarIdx = (_globalSlot < _barOfSlot.length) ? _barOfSlot[_globalSlot] : 0;
    final currentLyric = currentBarIdx < fSong.bars.length ? fSong.bars[currentBarIdx].lyric : null;

    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(children: [
          Text(fSong.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          if (fSong.subtitle.isNotEmpty) ...[
            const SizedBox(width: 8),
            Flexible(child: Text(fSong.subtitle, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant), overflow: TextOverflow.ellipsis)),
          ],
          const Spacer(),
          Text('第 ${currentBarIdx + 1}/${fSong.bars.length} 小节', style: TextStyle(fontSize: 12, color: cs.primary)),
        ]),
      ),
      Expanded(
        flex: 3,
        child: TablatureView(
          notes: _flatSlots.map((s) => s.shouldPlay
              ? TabNote(stringIndex: s.stringIndex!, fret: s.fret, duration: s.duration)
              : TabNote.rest(duration: s.duration)).toList(),
          currentSlot: _globalSlot.clamp(0, _flatSlots.length - 1),
          barStarts: _barStarts,
        ),
      ),
      // 当前歌词条(预备拍时显示倒计时)
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: cs.surfaceContainerHighest, border: Border(top: BorderSide(color: cs.outlineVariant))),
        child: _inCountIn
            ? Text('预备 ${_countInSlot ~/ 4 + 1}', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: cs.primary))
            : Text(currentLyric ?? '♪', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, color: cs.primary, fontWeight: FontWeight.w600)),
      ),
      // 跟练/听曲谱 提示(第79步):让"关掉示范音就能自己弹"一眼看到。
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Text(
          _soundOn
              ? '💡 听曲谱中 · 关掉「示范音」就能跟练(节拍器打拍,自己跟着高亮弹)'
              : '✋ 跟练中 · 跟着高亮的音 + 嗒声,自己弹出来',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
        ),
      ),
      _buildControlBar(cs),
    ]);
  }

  Widget _buildControlBar(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(color: cs.surfaceContainerLow, border: Border(top: BorderSide(color: cs.outlineVariant))),
      child: Row(children: [
        IconButton(
          onPressed: widget.audio.isReady ? _togglePlay : null,
          tooltip: _playing ? '暂停' : '开始',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
          style: IconButton.styleFrom(foregroundColor: cs.primary, disabledForegroundColor: cs.onSurfaceVariant.withValues(alpha: 0.4)),
        ),
        const SizedBox(width: 4),
        IconButton(
          onPressed: () { setState(() => _soundOn = !_soundOn); _prefs?.setFingerpickSound(_soundOn); },
          tooltip: _soundOn ? '示范音:开(听曲谱)' : '示范音:关(跟练 · 节拍器打拍,自己弹)',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          icon: Icon(_soundOn ? Icons.graphic_eq : Icons.volume_off),
          style: IconButton.styleFrom(foregroundColor: _soundOn ? cs.primary : cs.onSurfaceVariant),
        ),
        const SizedBox(width: 8),
        Text('$_tempo BPM', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
        Expanded(child: Slider(
          value: _tempo.toDouble(), min: 40, max: 180,
          onChanged: (v) { setState(() => _tempo = v.round()); _restartTimerIfPlaying(); _prefs?.setFingerpickTempo(_tempo); },
        )),
      ]),
    );
  }

  void _restartTimerIfPlaying() {
    if (_playing) { _timer?.cancel(); _timer = Timer.periodic(_tickDuration, (_) => _onTick()); }
  }
}
