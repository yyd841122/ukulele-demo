// 琶音织体练习页(独立 tab)。
// 跟指弹 tab(旋律 TAB 跟练)、练习 tab(扫弦弹唱)都不同:这里练的是【在一个和弦上按顺序拨弦】的伴奏织体
// ——4321 琶音(依次拨 4→3→2→1,从低到高滚一遍)、4323 织体(4→3→2→3 循环,民谣抒情伴奏最常用)。
//
// 自带几条常用和弦进行(单和弦慢练 / 流行 1-5-6-4 / 经典 1-6-4-5 / 小调 6-4-1-5),反复套拨弦型练。
// 不接歌词 / AB 循环 / 移调:纯右手拨弦练习,固定 C/Am 调。
//
// 节奏走【半拍槽】(跟练习 tab 一个粒度):一小节 = beatsPerChord×2 个槽。
// 每个和弦从拨弦型第 0 个音起(和弦第一拍落在低音 G 上,符合伴奏习惯)。
// 开示范音 = 听拨弦(每槽按型拨当前和弦的某根弦,代替嗒);关示范音 = 跟练(只剩正拍嗒 + 高亮,自己拨)。
// 复用现成的 AudioEngine.playString(和弦名+弦号)——单音声源在 init 时已全量预生成,不用动音频层。
import 'dart:async';

import 'package:flutter/material.dart';

import '../audio/audio_engine.dart';
import '../models.dart';
import '../widgets/chord_diagram.dart';

class ArpeggioScreen extends StatefulWidget {
  final AudioEngine audio;

  const ArpeggioScreen({required this.audio, super.key});

  @override
  State<ArpeggioScreen> createState() => ArpeggioScreenState();
}

class ArpeggioScreenState extends State<ArpeggioScreen> {
  int _selectedStudy = 0;
  int _selectedPattern = 0;

  // 播放状态
  bool _playing = false;
  bool _soundOn = true;          // 示范音:开=听拨弦;关=跟练(只剩节拍器嗒 + 高亮,自己拨)
  late int _tempo;               // 跟着选中的练习走(换进行时同步)
  Timer? _timer;
  bool _inCountIn = false;       // 预备拍阶段
  int _countInSlot = 0;          // 预备拍已走的半拍槽(0..slotsPerBar-1)
  bool _everPlayed = false;      // 这条进行正式播过(用来决定是否再数预备拍)

  int _slot = 0;                 // 当前半拍槽(0..beatsPerChord*2-1),正式播放用
  int _chordIdx = 0;             // 当前第几个和弦

  ArpStudy get _study =>
      builtinArpStudies[_selectedStudy.clamp(0, builtinArpStudies.length - 1)];
  ArpPattern get _pattern =>
      builtinArpPatterns[_selectedPattern.clamp(0, builtinArpPatterns.length - 1)];
  int get _slotsPerBar => _study.beatsPerChord * 2;

  /// 一个半拍的时长 = 60000/BPM/2 ms。
  Duration get _halfBeat => Duration(milliseconds: (30000 / _tempo).round());

  @override
  void initState() {
    super.initState();
    _tempo = _study.tempo;
  }

  void _resetPos() {
    _slot = 0;
    _chordIdx = 0;
    _inCountIn = false;
    _everPlayed = false;
    _countInSlot = 0;
  }

  // —— 换进行 / 换拨弦型 ——
  void _onStudyChanged(int i) {
    _stop();
    setState(() {
      _selectedStudy = i;
      _tempo = _study.tempo;
      _resetPos();
    });
  }

  void _onPatternChanged(int i) {
    // 不停、不重置位置:拨弦型每槽现算,换了一下一槽就生效。
    setState(() => _selectedPattern = i);
  }

  // —— 播放控制 ——
  void _togglePlay() {
    if (_playing) {
      _stop();
      return;
    }
    if (!widget.audio.isReady) return;

    if (!_everPlayed) {
      // 第一次:从头 + 数一小节预备拍
      _resetPos();
      _inCountIn = true;
    }
    // 否则:暂停后恢复,接着当前位置播(不重数预备拍)
    setState(() => _playing = true);
    _timer = Timer.periodic(_halfBeat, (_) => _onTick());
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    if (_playing) setState(() => _playing = false);
  }

  /// 定时器每一下(一个半拍槽)。预备拍阶段嗒声倒计时一小节;正式阶段推进槽位 + 拨弦/嗒。
  void _onTick() {
    if (_inCountIn) {
      // 预备拍:正拍(偶数槽)嗒一声,第 1 拍重音。
      if (_countInSlot.isEven) widget.audio.playClick(accent: _countInSlot == 0);
      _countInSlot++;
      if (_countInSlot >= _slotsPerBar) {
        // 预备拍数完一小节 → 正式第 1 拍:落到 slot0/chord0,拨第一根弦。
        _inCountIn = false;
        _everPlayed = true;
        _slot = 0;
        _chordIdx = 0;
        _playCurrent();
      }
    } else {
      _slot++;
      if (_slot >= _slotsPerBar) {
        _slot = 0;
        _chordIdx = (_chordIdx + 1) % _study.chords.length; // 末尾循环回 0
      }
      _playCurrent();
    }
    setState(() {});
  }

  /// 走一下:示范音开 → 按型拨当前和弦的某根弦(代替嗒);关 → 正拍嗒一声(跟练)。
  void _playCurrent() {
    final chord = _study.chords[_chordIdx];
    if (_soundOn) {
      final s = arpStringAt(_pattern, _study.beatsPerChord, _slot);
      if (s != null) widget.audio.playString(chord, s);
      // s == null(一拍一音型的后半拍):不拨,让上一音延续。
    } else {
      // 跟练:正拍嗒一声给拍子参考(偶数槽),不拨弦。
      if (_slot.isEven) widget.audio.playClick(accent: _slot == 0);
    }
  }

  void _restartTimerIfPlaying() {
    if (_playing) {
      _timer?.cancel();
      _timer = Timer.periodic(_halfBeat, (_) => _onTick());
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
      appBar: _buildAppBar(cs, theme),
      body: _buildBody(cs, theme),
    );
  }

  PreferredSizeWidget _buildAppBar(ColorScheme cs, ThemeData theme) {
    return AppBar(
      title: DropdownButton<int>(
        value: _selectedStudy,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        items: [
          for (var i = 0; i < builtinArpStudies.length; i++)
            DropdownMenuItem(
              value: i,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(builtinArpStudies[i].title, style: theme.textTheme.titleSmall),
                  if ((builtinArpStudies[i].subtitle ?? '').isNotEmpty)
                    Text(builtinArpStudies[i].subtitle!,
                        style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
        ],
        onChanged: (i) { if (i != null) _onStudyChanged(i); },
        dropdownColor: cs.surface,
        style: theme.textTheme.titleMedium?.copyWith(color: cs.onSurface),
      ),
    );
  }

  Widget _buildBody(ColorScheme cs, ThemeData theme) {
    final study = _study;
    final chord = study.chords[_chordIdx.clamp(0, study.chords.length - 1)];
    final nextChord = study.chords[(_chordIdx + 1) % study.chords.length];

    return Column(children: [
      // 拨弦型选择
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('拨弦型', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          const SizedBox(height: 2),
          Wrap(spacing: 6, children: [
            for (var i = 0; i < builtinArpPatterns.length; i++)
              ChoiceChip(
                label: Text(builtinArpPatterns[i].name, style: const TextStyle(fontSize: 12)),
                selected: i == _selectedPattern,
                onSelected: (_) => _onPatternChanged(i),
                visualDensity: VisualDensity.compact,
              ),
          ]),
        ]),
      ),
      // 可视化区:当前和弦图 + 拨弦序列(高亮当前)+ 进行点
      Expanded(
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // 当前和弦名 + 指法图
            Text(chord, style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold, color: cs.primary)),
            const SizedBox(height: 4),
            chordShapes.containsKey(chord)
                ? ChordDiagram(frets: chordShapes[chord]!, scale: 1.8)
                : Text(chord, style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            // 拨弦序列(当前这组和弦上要拨的弦号,高亮正在拨的那根)
            _buildArpGrid(cs),
            const SizedBox(height: 14),
            // 和弦进行点
            _buildChordDots(cs),
            const SizedBox(height: 8),
            if (!_inCountIn)
              Text('下一个: $nextChord', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          ]),
        ),
      ),
      // 预备拍倒计时 / 跟练·听 提示
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(color: cs.surfaceContainerHighest, border: Border(top: BorderSide(color: cs.outlineVariant))),
        child: _inCountIn
            ? Text('预备 ${_countInSlot ~/ 2 + 1}', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: cs.primary))
            : Text(
                _soundOn
                    ? '💡 听拨弦中 · 关掉「示范音」就能跟练(节拍器打拍,自己照高亮拨)'
                    : '✋ 跟练中 · 照高亮的弦号 + 嗒声,自己拨出来',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
      ),
      _buildControlBar(cs),
    ]);
  }

  /// 当前和弦的拨弦序列:按拍分组,高亮正在拨(或正在响)的那根。物理弦号 = 4 - stringIndex。
  Widget _buildArpGrid(ColorScheme cs) {
    final bpc = _study.beatsPerChord;
    final pat = _pattern;
    // 当前正在响的那下对应的槽(一拍一音型:后半拍时前半拍那音还在响 → 回退一格)。
    final activeSlot = (pat.notesPerBeat == 1 && _slot.isOdd) ? _slot - 1 : _slot;

    final chips = <Widget>[];
    for (var slot = 0; slot < _slotsPerBar; slot++) {
      final s = arpStringAt(pat, bpc, slot);
      if (s == null) continue; // 休止槽不显示
      // 拍与拍之间留宽间隙(每组拍的第 1 个音前),组内窄间隙。
      final beatStart = (pat.notesPerBeat == 1) ? slot.isEven : slot.isEven;
      if (chips.isNotEmpty) chips.add(SizedBox(width: beatStart ? 16 : 6));
      final active = slot == activeSlot && !_inCountIn;
      chips.add(_stringChip(cs, '${4 - s}', active));
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: chips),
    );
  }

  Widget _stringChip(ColorScheme cs, String label, bool active) {
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? cs.primary : cs.surfaceContainerHighest,
        border: Border.all(color: active ? cs.primary : cs.outlineVariant, width: active ? 2 : 1),
      ),
      child: Text(label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: active ? cs.onPrimary : cs.onSurfaceVariant,
          )),
    );
  }

  /// 和弦进行点:C G Am F…,当前点亮。
  Widget _buildChordDots(ColorScheme cs) {
    final study = _study;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var i = 0; i < study.chords.length; i++) ...[
          if (i > 0) Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.chevron_right_rounded, size: 16, color: cs.outline)),
          Text(
            study.chords[i],
            style: TextStyle(
              fontSize: i == _chordIdx ? 18 : 14,
              fontWeight: FontWeight.bold,
              color: i == _chordIdx ? cs.primary : cs.outline,
            ),
          ),
        ],
      ]),
    );
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
          tooltip: _soundOn ? '示范音:开(听拨弦)' : '示范音:关(跟练 · 节拍器打拍,自己拨)',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          icon: Icon(_soundOn ? Icons.graphic_eq : Icons.volume_off),
          style: IconButton.styleFrom(foregroundColor: _soundOn ? cs.primary : cs.onSurfaceVariant),
        ),
        const SizedBox(width: 8),
        Text('$_tempo BPM', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
        Expanded(child: Slider(
          value: _tempo.clamp(40, 180).toDouble(), min: 40, max: 180, divisions: 140,
          label: '$_tempo BPM',
          onChanged: (v) { setState(() => _tempo = v.round()); _restartTimerIfPlaying(); },
        )),
      ]),
    );
  }
}
