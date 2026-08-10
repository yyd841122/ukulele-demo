// 指弹练习页(第69步):独立 tab,选歌+指弹型+TAB 曲谱+播放控制。
// 跟练习页(SongScreen)是平级 tab,共享 AudioEngine。
//
// 核心循环:选歌 → 拍扁和弦序列 → 选指弹型 → generateTabNotes 生成 TAB 谱 →
// ▶ 逐槽播放 + TAB 谱逐槽高亮 + 自动滚动。
// 定时器复用 SongScreen 套路:_halfBeat 粒度、_slot/_idx 推进、预备拍倒计时。
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

class FingerpickScreenState extends State<FingerpickScreen> {
  List<Song> get songs => widget.store.songs;

  int _selected = 0;                 // 选中歌下标
  int _patternIndex = 0;             // 指弹型下标(0-7)
  int _tempo = 120;                  // 当前速度 BPM
  bool _playing = false;
  bool _strumSoundOn = true;         // 这里=指弹声开关
  int _slot = 0;                     // 当前槽位
  int _idx = 0;                      // 当前在 _flat 里的下标
  Timer? _timer;
  bool _inCountIn = false;
  bool _everPlayed = false;

  List<String> _flat = [];
  List<TabNote> _tabNotes = [];
  int _transpose = 0;

  AppPreferences? _prefs;

  Duration get _halfBeat => Duration(milliseconds: (30000 / _tempo).round());

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChanged);
    _rebuild();
    _loadPrefs();
  }

  void _onStoreChanged() {
    if (!mounted || songs.isEmpty) return;
    setState(() => _selected = _selected.clamp(0, songs.length - 1));
    _rebuild();
  }

  Future<void> _loadPrefs() async {
    final p = await AppPreferences.load();
    if (!mounted) return;
    setState(() {
      _prefs = p;
      final id = p.getSelectedSongId();
      final found = songs.indexWhere((s) => s.id == id);
      _selected = (found < 0 ? _selected : found).clamp(0, songs.length - 1);
      _tempo = p.getTempo(songs[_selected].id) ?? songs[_selected].tempo;
      _transpose = p.getTranspose(songs[_selected].id);
      _patternIndex = p.getFingerpickPattern(songs[_selected].id).clamp(0, 7);
      _rebuild();
    });
  }

  void _rebuild() {
    if (songs.isEmpty) return;
    final song = songs[_selected];
    _flat = [];
    for (final s in song.sections) {
      for (final l in s.lines) {
        _flat.addAll(l.chords);
      }
    }
    _tabNotes = generateTabNotes(_flat, fingerpickPatternsFor(song.beatsPerChord)[_patternIndex.clamp(0, 7)], song.beatsPerChord);
  }

  void _onSongChanged(int i) {
    _stop();
    final p = _prefs;
    if (p != null) {
      p.setTempo(songs[_selected].id, _tempo);
      p.setTranspose(songs[_selected].id, _transpose);
      p.setFingerpickPattern(songs[_selected].id, _patternIndex);
    }
    setState(() {
      _selected = i;
      _slot = 0;
      _idx = 0;
      _tempo = p?.getTempo(songs[i].id) ?? songs[i].tempo;
      _transpose = p?.getTranspose(songs[i].id) ?? 0;
      _patternIndex = (p?.getFingerpickPattern(songs[i].id) ?? 0).clamp(0, 7);
      _rebuild();
    });
    p?.setSelectedSongId(songs[i].id);
  }

  void _setTempo(int v) {
    if (v == _tempo) return;
    setState(() => _tempo = v);
    _restartTimerIfPlaying();
  }

  void _restartTimerIfPlaying() {
    if (_playing) { _timer?.cancel(); _startTimer(); }
  }

  void _startTimer() {
    _timer = Timer.periodic(_halfBeat, (_) => _onTimerTick());
  }

  void _onTimerTick() {
    final song = songs[_selected];
    final slotsPerBar = song.beatsPerChord * 2;
    _slot++;
    if (_slot >= slotsPerBar) {
      _slot = 0;
      if (_inCountIn) {
        _inCountIn = false;
        _everPlayed = true;
      } else if (_flat.isNotEmpty) {
        // 整曲循环: _idx 推进,到末尾归零
        if (_idx + 1 >= _flat.length) {
          _idx = 0;
        } else {
          _idx++;
        }
      }
    }
    _tick();
  }

  void _tick() {
    if (_inCountIn) {
      if (_slot.isEven) widget.audio.playClick(accent: _slot == 0);
    } else if (_strumSoundOn && _flat.isNotEmpty && _idx < _flat.length) {
      final song = songs[_selected];
      final fp = fingerpickPatternsFor(song.beatsPerChord)[_patternIndex.clamp(0, 7)];
      final grid = fp.grid(song.beatsPerChord);
      final si = (_slot >= 0 && _slot < grid.length) ? grid[_slot] : null;
      if (si != null) widget.audio.playString(_flat[_idx], si, semis: _transpose);
    } else {
      if (_slot.isEven) widget.audio.playClick(accent: _slot == 0);
    }
    setState(() {});
  }

  void _togglePlay() {
    if (_playing) {
      _stop();
      return;
    }
    if (!widget.audio.isReady) return;
    if (!_everPlayed) {
      setState(() {
        _inCountIn = true;
        _slot = 0;
        _idx = 0;
      });
    }
    setState(() => _playing = true);
    _startTimer();
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    if (_playing) setState(() => _playing = false);
  }

  /// MainScaffold 切走本 tab 时调用。
  void stop() => _stop();

  @override
  void dispose() {
    _stop();
    widget.store.removeListener(_onStoreChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) return const Scaffold(body: Center(child: Text('没有歌')));
    final song = songs[_selected];
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final fps = fingerpickPatternsFor(song.beatsPerChord);

    // TAB 谱当前高亮槽位:指弹型的一个"bar"(beatsPerChord×2 槽)对应 _flat 里一个和弦;
    // _idx 决定第几个和弦,_slot 决定和弦内第几个槽。
    final tabSlot = _idx * song.beatsPerChord * 2 + _slot;

    return Scaffold(
      appBar: AppBar(
        title: DropdownButton<int>(
          value: _selected,
          isExpanded: true,
          underline: const SizedBox.shrink(),
          items: [
            for (var i = 0; i < songs.length; i++)
              DropdownMenuItem(value: i, child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
                child: Text(songs[i].title))),
          ],
          onChanged: (i) { if (i != null) _onSongChanged(i); },
          dropdownColor: cs.surface,
          style: theme.textTheme.titleMedium?.copyWith(color: cs.onSurface),
          icon: Icon(Icons.arrow_drop_down, color: cs.onSurface),
        ),
        actions: [
          // 移调入�(复用)
          IconButton(icon: const Icon(Icons.tune), tooltip: '移调',
            onPressed: _showTransposeDialog,
            color: _transpose != 0 ? cs.primary : null,
          ),
        ],
      ),
      body: Column(
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
                      _prefs?.setFingerpickPattern(songs[_selected].id, i);
                      _rebuild();
                    },
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
          // 状态行
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
          // TAB 谱
          Expanded(
            child: TablatureView(
              notes: _tabNotes,
              currentSlot: tabSlot.clamp(0, _tabNotes.length - 1),
              beatsPerChord: song.beatsPerChord,
            ),
          ),
          // 控制栏
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              border: Border(top: BorderSide(color: cs.outlineVariant)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ▶/⏸ + 调速
                Row(
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
                      onPressed: () { setState(() => _strumSoundOn = !_strumSoundOn); },
                      tooltip: _strumSoundOn ? '指弹声:开' : '指弹声:关',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      icon: Icon(_strumSoundOn ? Icons.graphic_eq : Icons.volume_off),
                      style: IconButton.styleFrom(foregroundColor: _strumSoundOn ? cs.primary : cs.onSurfaceVariant),
                    ),
                    const SizedBox(width: 8),
                    Text('$_tempo BPM', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
                    Expanded(
                      child: Slider(
                        value: _tempo.toDouble(),
                        min: (song.tempo / 2).round().toDouble(),
                        max: (song.tempo * 2).round().toDouble(),
                        onChanged: (v) => _setTempo(v.round()),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

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
                    _transpose == 0 ? '原调' : '$sign$_transpose 半音',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(ctx).colorScheme.primary),
                  ),
                  Slider(
                    value: _transpose.toDouble(),
                    min: -6, max: 6, divisions: 12,
                    label: '$_transpose',
                    onChanged: (v) {
                      setSt(() => _transpose = v.round());
                      setState(() => _transpose = v.round());
                      _prefs?.setTranspose(songs[_selected].id, _transpose);
                      widget.audio.prepareTranspose(_transpose);
                      _rebuild(); // 移调影响品位:rebuild TAB 谱(品位不变,这里只是确保 rebuild)
                    },
                  ),
                ],
              ),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('完成'))],
            );
          },
        );
      },
    );
  }
}
