// 指弹练习页(第69步/第75步/第78步重构)。
// 独立 tab,两个子模式:① 真实指弹曲谱播放(小星星/卡农/绿袖子/千与千寻),② 自动生成练习。
//
// 第78步核心修复:节奏推进改成 tick 累积——每个 16 分 tick 累加 _ticksHeld,
// 达到当前音的 duration 才推进到下一个音。这样四分音符(duration=4)真的占 4 个 tick = 1 拍。
// (旧 bug: _globalSlot += duration,相邻音只隔 1 tick,节奏快了 N 倍)
import 'dart:async';

import 'package:flutter/material.dart';

import '../audio/audio_engine.dart';
import '../models.dart';
import '../prefs/app_preferences.dart';
import '../scoring/tab_generator.dart';
import '../song_store.dart';
import '../widgets/fretboard_view.dart';

class FingerpickScreen extends StatefulWidget {
  final AudioEngine audio;
  final SongStore store;

  const FingerpickScreen({required this.audio, required this.store, super.key});

  @override
  State<FingerpickScreen> createState() => FingerpickScreenState();
}

enum _FpMode { practice, score }

class FingerpickScreenState extends State<FingerpickScreen> {
  List<Song> get songs => widget.store.songs;

  _FpMode _mode = _FpMode.score;
  int _selectedScore = 0;
  int _patternIndex = 0;

  // 播放状态
  bool _playing = false;
  bool _soundOn = true;
  int _tempo = 85;
  Timer? _timer;
  bool _inCountIn = false;       // 预备拍阶段
  bool _everPlayed = false;      // 这首歌正式播过(用来决定是否再数预备拍)
  int _countInSlot = 0;          // 预备拍已走的 16 分 tick(0..15)
  bool _pendingStart = false;    // 预备拍刚结束,下一 tick 播第一个音(修过渡早1tick)

  // —— 曲谱模式 ——
  List<FingerpickSlot> _flatSlots = []; // 拍扁的所有音
  int _globalSlot = 0;           // 当前第几个音(在 _flatSlots 里)
  int _ticksHeld = 0;            // 当前音已持续多少个 16 分 tick
  List<int> _barStarts = [];     // 每小节起始 slot 下标(画小节线)
  List<int> _barOfSlot = [];     // 每个 slot 属于第几小节

  // —— 练习模式 ——
  List<String> _flat = [];
  List<TabNote> _tabNotes = [];
  int _selectedSong = 0;
  int _slot = 0;
  int _idx = 0;
  List<int> _practiceBarStarts = [];

  AppPreferences? _prefs;

  /// 一个 16 分音符 tick 的时长。曲谱/练习都用 16 分粒度(练习模式数据按 8 分=duration 2)。
  Duration get _tickDuration => Duration(milliseconds: (15000 / _tempo).round());

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChanged);
    _rebuildScoreSlots();
    _loadPrefs();
  }

  void _onStoreChanged() {
    if (!mounted) return;
    // 歌单变了(加/删歌):练习模式的 _selectedSong 可能越界 → 夹回合法范围 + 重建数据。
    // 不处理的话 _buildPracticeBody 的 songs[_selectedSong] 会 RangeError 崩。
    if (songs.isNotEmpty && _selectedSong >= songs.length) {
      _selectedSong = songs.length - 1;
      _rebuildPractice();
    }
    setState(() {});
  }

  Future<void> _loadPrefs() async {
    final p = await AppPreferences.load();
    if (!mounted) return;
    setState(() {
      _prefs = p;
      // 练习模式的指弹型用全局 key 'practice'(不绑具体歌);曲谱模式自带数据不用 prefs。
      _patternIndex = p.getFingerpickPattern('practice').clamp(0, 7);
    });
  }

  // —— 曲谱模式:拍扁 + 建小节映射 ——
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

  // —— 练习模式 ——
  void _rebuildPractice() {
    if (songs.isEmpty) return;
    final song = songs[_selectedSong];
    _flat = [];
    for (final s in song.sections) {
      for (final l in s.lines) {
        _flat.addAll(l.chords);
      }
    }
    _tabNotes = generateTabNotes(_flat, fingerpickPatternsFor(song.beatsPerChord)[_patternIndex.clamp(0, 7)], song.beatsPerChord);
    _tempo = _prefs?.getTempo(song.id) ?? song.tempo;
    // 练习模式:每 beatsPerChord*2 个 slot 一小节,每个 slot 时值=2(8分音符,视觉宽点)
    final perBar = song.beatsPerChord * 2;
    _practiceBarStarts = [for (var i = 0; i < _tabNotes.length; i += perBar) if (i < _tabNotes.length) i];
    _resetPlayPos();
  }

  void _resetPlayPos() {
    _globalSlot = 0;
    _ticksHeld = 0;
    _slot = 0;
    _idx = 0;
    _inCountIn = false;
    _everPlayed = false;
    _countInSlot = 0;
    _pendingStart = false;
  }

  // —— 播放控制 ——
  void _togglePlay() {
    if (_playing) { _stop(); return; }
    if (!widget.audio.isReady) return;

    if (_mode == _FpMode.score) {
      if (!_everPlayed) {
        // 第一次:从头 + 数预备拍
        _globalSlot = 0;
        _ticksHeld = 0;
        _inCountIn = true;
        _countInSlot = 0;
      }
      // 否则:暂停后恢复,接着当前位置播(不重数预备拍)
    } else {
      if (!_everPlayed) {
        _slot = 0; _idx = 0;
        _inCountIn = true;
        _countInSlot = 0;
      }
    }
    setState(() => _playing = true);
    _timer = Timer.periodic(_tickDuration, (_) => _onTick());
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    if (_playing) setState(() => _playing = false);
  }

  /// MainScaffold 切走时调。
  void stop() => _stop();

  void _onTick() {
    if (_mode == _FpMode.score) {
      _tickScore();
    } else {
      _tickPractice();
    }
    setState(() {});
  }

  /// 曲谱模式:每 16 分 tick 一次。预备拍阶段嗒声倒计时;正式阶段按当前音 duration 累积 tick。
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

    // 预备拍刚结束:这一 tick 是整曲第 1 拍的强位,播 slot0。
    if (_pendingStart) {
      _pendingStart = false;
      _globalSlot = 0;
      _ticksHeld = 0;
      _playSlot(0);
      return;
    }

    // 正式:_ticksHeld 累积。达到当前音的 duration 才推进到下一个音。
    _ticksHeld++;
    final cur = _flatSlots[_globalSlot];
    final dur = cur.duration <= 0 ? 1 : cur.duration;
    if (_ticksHeld >= dur) {
      _ticksHeld = 0;
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

  /// 练习模式:8 分音符槽位,每 2 个 16 分 tick 推一个槽(修"快2倍")。
  void _tickPractice() {
    final song = songs.isNotEmpty ? songs[_selectedSong] : null;
    if (song == null) return;

    if (_inCountIn) {
      if (_countInSlot % 4 == 0) widget.audio.playClick(accent: _countInSlot == 0);
      _countInSlot++;
      if (_countInSlot >= 16) {
        _inCountIn = false;
        _everPlayed = true;
        _pendingStart = true;
      }
      return;
    }

    if (_pendingStart) {
      _pendingStart = false;
      _slot = 0;
      _ticksHeld = 0;
      _playPracticeSlot();
      return;
    }

    // 8 分音符 = 2 个 16 分 tick。累积到 2 才推进一个槽。
    _ticksHeld++;
    if (_ticksHeld >= 2) {
      _ticksHeld = 0;
      _slot++;
      if (_slot >= song.beatsPerChord * 2) {
        _slot = 0;
        if (_flat.isNotEmpty) {
          if (_idx + 1 >= _flat.length) { _idx = 0; } else { _idx++; }
        }
      }
      _playPracticeSlot();
    }
  }

  void _playPracticeSlot() {
    if (!_soundOn || _flat.isEmpty || _idx >= _flat.length) return;
    final song = songs[_selectedSong];
    final fps = fingerpickPatternsFor(song.beatsPerChord);
    final fp = fps[_patternIndex.clamp(0, fps.length - 1)];
    final grid = fp.grid(song.beatsPerChord);
    final si = (_slot >= 0 && _slot < grid.length) ? grid[_slot] : null;
    if (si != null) widget.audio.playString(_flat[_idx], si);
  }

  @override
  void dispose() {
    _stop();
    widget.store.removeListener(_onStoreChanged);
    super.dispose();
  }

  // —— UI ——
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: _mode == _FpMode.score ? _buildScoreAppBar(cs, theme) : _buildPracticeAppBar(cs, theme),
      body: _mode == _FpMode.score ? _buildScoreBody(cs, theme) : _buildPracticeBody(cs, theme),
    );
  }

  PreferredSizeWidget _buildAppBarWithMode(ColorScheme cs, ThemeData theme, Widget trailing) {
    return AppBar(
      title: Row(children: [
        SegmentedButton<_FpMode>(
          segments: const [
            ButtonSegment(value: _FpMode.score, label: Text('曲谱', style: TextStyle(fontSize: 11))),
            ButtonSegment(value: _FpMode.practice, label: Text('练习', style: TextStyle(fontSize: 11))),
          ],
          selected: {_mode},
          onSelectionChanged: (v) {
            _stop();
            setState(() { _mode = v.first; });
            if (_mode == _FpMode.practice) _rebuildPractice(); else _rebuildScoreSlots();
          },
          style: ButtonStyle(visualDensity: VisualDensity.compact, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        ),
        const SizedBox(width: 8),
        Expanded(child: trailing),
      ]),
    );
  }

  PreferredSizeWidget _buildScoreAppBar(ColorScheme cs, ThemeData theme) {
    return _buildAppBarWithMode(cs, theme, DropdownButton<int>(
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
      onChanged: (i) { if (i != null) { _stop(); setState(() => _selectedScore = i); _rebuildScoreSlots(); } },
      dropdownColor: cs.surface,
      style: theme.textTheme.titleMedium?.copyWith(color: cs.onSurface),
    ));
  }

  PreferredSizeWidget _buildPracticeAppBar(ColorScheme cs, ThemeData theme) {
    return _buildAppBarWithMode(cs, theme, songs.isEmpty
        ? const Text('没有歌')
        : DropdownButton<int>(
            value: _selectedSong,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            items: [for (var i = 0; i < songs.length; i++) DropdownMenuItem(value: i, child: Text(songs[i].title, style: theme.textTheme.titleSmall))],
            onChanged: (i) { if (i != null) { _stop(); setState(() => _selectedSong = i); _rebuildPractice(); } },
            dropdownColor: cs.surface,
            style: theme.textTheme.titleMedium?.copyWith(color: cs.onSurface),
          ));
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
      _buildControlBar(cs),
    ]);
  }

  Widget _buildPracticeBody(ColorScheme cs, ThemeData theme) {
    if (songs.isEmpty) return const Center(child: Text('没有歌'));
    final song = songs[_selectedSong];
    final fps = fingerpickPatternsFor(song.beatsPerChord);
    final tabSlot = _idx * song.beatsPerChord * 2 + _slot;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Wrap(spacing: 6, children: [
          for (var i = 0; i < fps.length; i++)
            ChoiceChip(
              label: Text(fps[i].name, style: const TextStyle(fontSize: 12)),
              selected: i == _patternIndex,
              onSelected: (_) { _stop(); setState(() => _patternIndex = i); _prefs?.setFingerpickPattern('practice', i); _rebuildPractice(); },
              visualDensity: VisualDensity.compact,
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Text('${song.title} · ${song.tempo} BPM', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          const Spacer(),
          Text('第 ${_idx + 1}/${_flat.length} 和弦', style: TextStyle(fontSize: 12, color: cs.primary)),
        ]),
      ),
      const SizedBox(height: 4),
      Expanded(
        child: TablatureView(
          notes: [for (final n in _tabNotes) TabNote(stringIndex: n.stringIndex, fret: n.fret, isRest: n.isRest, duration: 2)],
          currentSlot: tabSlot.clamp(0, _tabNotes.length - 1),
          barStarts: _practiceBarStarts,
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
          onPressed: () => setState(() => _soundOn = !_soundOn),
          tooltip: _soundOn ? '指弹声:开' : '指弹声:关',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          icon: Icon(_soundOn ? Icons.graphic_eq : Icons.volume_off),
          style: IconButton.styleFrom(foregroundColor: _soundOn ? cs.primary : cs.onSurfaceVariant),
        ),
        const SizedBox(width: 8),
        Text('$_tempo BPM', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
        Expanded(child: Slider(
          value: _tempo.toDouble(), min: 40, max: 180,
          onChanged: (v) { setState(() => _tempo = v.round()); _restartTimerIfPlaying(); },
        )),
      ]),
    );
  }

  void _restartTimerIfPlaying() {
    if (_playing) { _timer?.cancel(); _timer = Timer.periodic(_tickDuration, (_) => _onTick()); }
  }
}
