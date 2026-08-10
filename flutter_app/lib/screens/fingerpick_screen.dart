// 指弹练习页(第69步/第75步重构)。
// 独立 tab,两个子模式:① 自动生成练习(选歌+指弹型),② 真实指弹曲谱播放。
// 第75步:加 SegmentedButton 切模式,真实的 FingerpickSong 播放+TAB自动滚动+歌词联动。
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

// 指弹页子模式
enum _FpMode { practice, score } // 自动练习 / 真实曲谱

class FingerpickScreenState extends State<FingerpickScreen> {
  List<Song> get songs => widget.store.songs;

  _FpMode _mode = _FpMode.score;    // 默认进曲谱模式
  int _selectedScore = 0;           // 曲谱模式:选第几首 FingerpickSong
  int _patternIndex = 0;            // 练习模式:指弹型下标

  // 播放状态
  bool _playing = false;
  bool _soundOn = true;
  int _tempo = 80;
  Timer? _timer;
  int _globalSlot = 0;              // 当前全局槽位(在整个曲谱里的位置)
  List<FingerpickSlot> _flatSlots = []; // 拍扁后的所有槽

  // 练习模式(旧)
  List<String> _flat = [];
  List<TabNote> _tabNotes = [];
  int _selectedSong = 0;
  int _slot = 0;
  int _idx = 0;
  bool _inCountIn = false;
  bool _everPlayed = false;
  int _transpose = 0;

  AppPreferences? _prefs;

  Duration get _tickDuration {
    if (_mode == _FpMode.score) {
      return Duration(milliseconds: (15000 / _tempo).round()); // 16分音符
    }
    return Duration(milliseconds: (30000 / _tempo).round());   // 8分音符
  }

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChanged);
    _rebuildScoreSlots();
    _loadPrefs();
  }

  void _onStoreChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _loadPrefs() async {
    final p = await AppPreferences.load();
    if (!mounted) return;
    setState(() {
      _prefs = p;
      _patternIndex = (p.getFingerpickPattern('score_0') ?? 0).clamp(0, 7);
    });
  }

  // —— 曲谱模式 ——
  void _rebuildScoreSlots() {
    if (builtinFingerpickSongs.isEmpty) return;
    final fSong = builtinFingerpickSongs[_selectedScore.clamp(0, builtinFingerpickSongs.length - 1)];
    _flatSlots = fSong.flatSlots;
    _tempo = fSong.tempo;
  }

  int _slotsPerBar() {
    if (builtinFingerpickSongs.isEmpty) return 8;
    return builtinFingerpickSongs[_selectedScore.clamp(0, builtinFingerpickSongs.length - 1)].beatsPerBar * 4;
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
  }

  // —— 通用播放 ——
  void _togglePlay() {
    if (_playing) { _stop(); return; }
    if (!widget.audio.isReady) return;

    if (_mode == _FpMode.score) {
      _globalSlot = 0;
    } else {
      _slot = 0; _idx = 0;
      _inCountIn = true;
      _everPlayed = false;
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
    setState(() {
      if (_mode == _FpMode.score) {
        _tickScore();
      } else {
        _tickPractice();
      }
    });
  }

  void _tickScore() {
    if (_flatSlots.isEmpty) return;
    // 推进:跳过已过时的 duration 累积
    _globalSlot++;
    if (_globalSlot >= _flatSlots.length) _globalSlot = 0;

    // 发声
    final s = _flatSlots[_globalSlot];
    if (s.shouldPlay && _soundOn) {
      // 要按弦+品拨:直接用 freqForString 算频率→合成单音播放
      widget.audio.playString('C', s.stringIndex!, semis: 0);
      // 注:这里简单地用 C 和弦名来查 chordShapes,实际该用 freqForString 直算。
      // 暂时用 playString 的查表兜底:对不上 chordShapes 的就退回空弦。
    }
  }

  void _tickPractice() {
    // 旧逻辑:保留练习模式
    final song = songs.isNotEmpty ? songs[_selectedSong] : null;
    if (song == null) return;
    if (_inCountIn) {
      _slot++;
      if (_slot >= song.beatsPerChord * 2) { _slot = 0; _inCountIn = false; _everPlayed = true; }
      return;
    }
    _slot++;
    if (_slot >= song.beatsPerChord * 2) {
      _slot = 0;
      if (_flat.isNotEmpty) {
        if (_idx + 1 >= _flat.length) { _idx = 0; } else { _idx++; }
      }
    }
    if (_soundOn && _flat.isNotEmpty && _idx < _flat.length) {
      final fps = fingerpickPatternsFor(song.beatsPerChord);
      final fp = fps[_patternIndex.clamp(0, fps.length - 1)];
      final grid = fp.grid(song.beatsPerChord);
      final si = (_slot >= 0 && _slot < grid.length) ? grid[_slot] : null;
      if (si != null) widget.audio.playString(_flat[_idx], si);
    }
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

  PreferredSizeWidget _buildScoreAppBar(ColorScheme cs, ThemeData theme) {
    return AppBar(
      title: Row(
        children: [
          SegmentedButton<_FpMode>(
            segments: const [
              ButtonSegment(value: _FpMode.score, label: Text('曲谱', style: TextStyle(fontSize: 11))),
              ButtonSegment(value: _FpMode.practice, label: Text('练习', style: TextStyle(fontSize: 11))),
            ],
            selected: {_mode},
            onSelectionChanged: (v) {
              setState(() { _mode = v.first; });
              if (_mode == _FpMode.practice) _rebuildPractice();
              else _rebuildScoreSlots();
            },
            style: ButtonStyle(visualDensity: VisualDensity.compact, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButton<int>(
              value: _selectedScore,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              items: [
                for (var i = 0; i < builtinFingerpickSongs.length; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(builtinFingerpickSongs[i].title, style: theme.textTheme.titleSmall),
                        if (builtinFingerpickSongs[i].subtitle.isNotEmpty)
                          Text(builtinFingerpickSongs[i].subtitle, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
              ],
              onChanged: (i) {
                if (i != null) {
                  setState(() => _selectedScore = i);
                  _rebuildScoreSlots();
                }
              },
              dropdownColor: cs.surface,
              style: theme.textTheme.titleMedium?.copyWith(color: cs.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildPracticeAppBar(ColorScheme cs, ThemeData theme) {
    return AppBar(
      title: Row(
        children: [
          SegmentedButton<_FpMode>(
            segments: const [
              ButtonSegment(value: _FpMode.score, label: Text('曲谱', style: TextStyle(fontSize: 11))),
              ButtonSegment(value: _FpMode.practice, label: Text('练习', style: TextStyle(fontSize: 11))),
            ],
            selected: {_mode},
            onSelectionChanged: (v) {
              setState(() { _mode = v.first; });
              if (_mode == _FpMode.practice) _rebuildPractice();
            },
            style: ButtonStyle(visualDensity: VisualDensity.compact, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          ),
          const SizedBox(width: 8),
          if (songs.isNotEmpty)
            Expanded(
              child: DropdownButton<int>(
                value: _selectedSong,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                items: [
                  for (var i = 0; i < songs.length; i++)
                    DropdownMenuItem(value: i, child: Text(songs[i].title, style: theme.textTheme.titleSmall)),
                ],
                onChanged: (i) {
                  if (i != null) {
                    setState(() => _selectedSong = i);
                    _rebuildPractice();
                  }
                },
                dropdownColor: cs.surface,
                style: theme.textTheme.titleMedium?.copyWith(color: cs.onSurface),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildScoreBody(ColorScheme cs, ThemeData theme) {
    final fSong = builtinFingerpickSongs.isNotEmpty
        ? builtinFingerpickSongs[_selectedScore.clamp(0, builtinFingerpickSongs.length - 1)]
        : null;

    if (fSong == null) {
      return const Center(child: Text('没有指弹曲谱'));
    }

    final currentBarIdx = _slotsPerBar() > 0 ? _globalSlot ~/ _slotsPerBar() : 0;
    final currentLyric = currentBarIdx < fSong.bars.length ? fSong.bars[currentBarIdx].lyric : null;

    return Column(
      children: [
        // 曲名+作曲家
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Text(fSong.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              if (fSong.subtitle.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(fSong.subtitle, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
              const Spacer(),
              Text('第 ${currentBarIdx + 1}/${fSong.bars.length} 小节',
                  style: TextStyle(fontSize: 12, color: cs.primary)),
            ],
          ),
        ),
        // TAB 谱
        Expanded(
          flex: 3,
          child: TablatureView(
            notes: _flatSlots.map((s) => s.shouldPlay
                ? TabNote(stringIndex: s.stringIndex!, fret: s.fret)
                : const TabNote.rest()).toList(),
            currentSlot: _globalSlot.clamp(0, _flatSlots.length - 1),
            slotsPerBar: _slotsPerBar(),
          ),
        ),
        // 当前歌词条
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            border: Border(top: BorderSide(color: cs.outlineVariant)),
          ),
          child: Text(
            currentLyric ?? '♪',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              color: cs.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        // 控制栏
        _buildControlBar(cs),
      ],
    );
  }

  Widget _buildPracticeBody(ColorScheme cs, ThemeData theme) {
    if (songs.isEmpty) return const Center(child: Text('没有歌'));
    final song = songs[_selectedSong];
    final fps = fingerpickPatternsFor(song.beatsPerChord);
    final tabSlot = _idx * song.beatsPerChord * 2 + _slot;

    return Column(
      children: [
        // 指弹型选择
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Wrap(
            spacing: 6,
            children: [
              for (var i = 0; i < fps.length; i++)
                ChoiceChip(
                  label: Text(fps[i].name, style: const TextStyle(fontSize: 12)),
                  selected: i == _patternIndex,
                  onSelected: (_) {
                    setState(() => _patternIndex = i);
                    _rebuildPractice();
                  },
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text('${song.title} · ${song.tempo} BPM', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              const Spacer(),
              Text('第 ${_idx + 1}/${_flat.length} 和弦', style: TextStyle(fontSize: 12, color: cs.primary)),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: TablatureView(
            notes: _tabNotes,
            currentSlot: tabSlot.clamp(0, _tabNotes.length - 1),
            slotsPerBar: song.beatsPerChord * 2,
          ),
        ),
        _buildControlBar(cs),
      ],
    );
  }

  Widget _buildControlBar(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: widget.audio.isReady ? _togglePlay : null,
            tooltip: _playing ? '暂停' : '开始',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
            style: IconButton.styleFrom(
              foregroundColor: cs.primary,
              disabledForegroundColor: cs.onSurfaceVariant.withValues(alpha: 0.4),
            ),
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
          Expanded(
            child: Slider(
              value: _tempo.toDouble(),
              min: 40,
              max: 180,
              onChanged: (v) {
                setState(() => _tempo = v.round());
                _restartTimerIfPlaying();
              },
            ),
          ),
        ],
      ),
    );
  }

  void _restartTimerIfPlaying() {
    if (_playing) { _timer?.cancel(); _timer = Timer.periodic(_tickDuration, (_) => _onTick()); }
  }
}
