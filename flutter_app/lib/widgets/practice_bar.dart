// 顶部练习栏(吸顶)部件 + 里面那一排的和弦卡。
// 从 main.dart 拆出(第19步重构)。数据全是父级(SongScreen)算好传进来的,自己没状态。
//
// 第60步:加指弹模式——奏法切换(扫弦/指弹)、指弹型选择、弦号显示(G·C·E·A)。
import 'package:flutter/material.dart';

import '../models.dart';
import 'chord_diagram.dart';

/// 顶部练习栏(吸顶):一排和弦卡 =【当前这一行】的和弦,弹到哪个、那张就变大指法图并高亮,其余当小参考。
/// 下面:节奏型选择 + AB 状态 + 这一组扫到第几下(一排 ↓/↑ 或弦号)+ 信息行 + 调速滑块。
/// 数据全是父级算好传进来的;它自己没状态,只负责显示。
class PracticeBar extends StatelessWidget {
  final List<String> lineChords;
  final int currentChordIndex;
  final int slot;
  final int beatsPerChord;
  final List<StrumDir> strumGrid;
  final List<String> patternNames;
  final int patternIndex;
  final ValueChanged<int> onPatternChanged;
  final bool abActive;
  final VoidCallback onClearAb;
  final int countInNumber;
  final String nextChord;
  final int tempo;
  final int minTempo;
  final int maxTempo;
  final ValueChanged<int> onTempoChanged;
  final bool isPlaying;
  final bool canPlay;
  final VoidCallback onTogglePlay;
  final bool strumSoundOn;
  final VoidCallback onToggleStrumSound;
  final bool rampOn;
  final VoidCallback onToggleRamp;
  final void Function(String chord)? onChordTap;
  final String metronomeSound;
  final List<String> metronomeSoundNames;
  final ValueChanged<String> onMetronomeSoundChanged;
  final bool fullscreen;
  final VoidCallback onToggleFullscreen;
  // 第60步:指弹
  final PlayStyle playStyle;
  final VoidCallback onTogglePlayStyle;
  final List<int?> fingerpickGrid;
  final List<String> fingerpickPatternNames;
  final int fingerpickPatternIndex;
  final ValueChanged<int> onFingerpickPatternChanged;

  const PracticeBar({
    super.key,
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
    required this.strumSoundOn,
    required this.onToggleStrumSound,
    required this.rampOn,
    required this.onToggleRamp,
    this.onChordTap,
    this.metronomeSound = 'click',
    this.metronomeSoundNames = const ['click', 'beep', 'wood', 'rim'],
    this.onMetronomeSoundChanged = _noopStr,
    this.fullscreen = false,
    this.onToggleFullscreen = _noopVoid,
    this.playStyle = PlayStyle.strum,
    this.onTogglePlayStyle = _noopVoid,
    this.fingerpickGrid = const [],
    this.fingerpickPatternNames = const [],
    this.fingerpickPatternIndex = 0,
    this.onFingerpickPatternChanged = _noopInt,
  });

  static void _noopInt(int _) {}
  static void _noopVoid() {}
  static void _noopStr(String _) {}

  /// 弦号→简短的显示字符(给指弹 grid)。
  /// 0=G, 1=C, 2=E, 3=A——跟 chordShapes frets 和 openTuning 顺序完全一致。
  static const _stringLabels = ['G', 'C', 'E', 'A'];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isFp = playStyle == PlayStyle.fingerpick;

    // 这一行的和弦卡
    final refCards = <Widget>[];
    for (var i = 0; i < lineChords.length; i++) {
      if (i > 0) refCards.add(const SizedBox(width: 8));
      refCards.add(
        _ChordRefCard(
          name: lineChords[i],
          isCurrent: i == currentChordIndex,
          onTap: onChordTap == null ? null : () => onChordTap!(lineChords[i]),
        ),
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
          // 一排和弦卡
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: refCards,
            ),
          ),
          const SizedBox(height: 6),
          // 奏法切换 + 节奏型/指弹型选择
          Wrap(
            spacing: 6,
            children: [
              // 扫弦/指弹 SegmentedButton
              SizedBox(
                height: 32,
                child: SegmentedButton<PlayStyle>(
                  segments: const [
                    ButtonSegment(value: PlayStyle.strum, label: Text('扫弦', style: TextStyle(fontSize: 11))),
                    ButtonSegment(value: PlayStyle.fingerpick, label: Text('指弹', style: TextStyle(fontSize: 11))),
                  ],
                  selected: {playStyle},
                  onSelectionChanged: (_) => onTogglePlayStyle(),
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // 按当前奏法显示对应的节奏型芯片
              if (isFp)
                for (var i = 0; i < fingerpickPatternNames.length; i++)
                  ChoiceChip(
                    label: Text(fingerpickPatternNames[i], style: const TextStyle(fontSize: 12)),
                    selected: i == fingerpickPatternIndex,
                    onSelected: (_) => onFingerpickPatternChanged(i),
                    visualDensity: VisualDensity.compact,
                  )
              else
                for (var i = 0; i < patternNames.length; i++)
                  ChoiceChip(
                    label: Text(patternNames[i], style: const TextStyle(fontSize: 12)),
                    selected: i == patternIndex,
                    onSelected: (_) => onPatternChanged(i),
                    visualDensity: VisualDensity.compact,
                  ),
            ],
          ),
          // AB 循环状态行
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: abActive
                ? Row(
                    children: [
                      Icon(Icons.repeat_rounded, size: 16, color: cs.primary),
                      const SizedBox(width: 4),
                      Text('AB 循环中',
                        style: TextStyle(fontSize: 12, color: cs.primary, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      IconButton(
                        onPressed: onClearAb,
                        tooltip: '清除 AB 区间',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        icon: const Icon(Icons.close_rounded, size: 18),
                        style: IconButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
                      ),
                    ],
                  )
                : Text('👆 点两行歌词设 AB 循环点(到 B 跳回 A 反复练)',
                    style: TextStyle(fontSize: 11, color: cs.outline)),
          ),
          const SizedBox(height: 4),
          // grid 显示:预备拍数字 or 扫弦 ↓/↑/· or 指弹弦号 G/C/E/A
          if (countInNumber > 0)
            Row(
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
                        color: i + 1 == countInNumber ? cs.primary : cs.outline,
                      ),
                    ),
                  ),
              ],
            )
          else if (isFp)
            // 指弹:显示弦号 G C E A
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < fingerpickGrid.length; i++) ...[
                  if (i > 0) SizedBox(width: i.isEven ? 14 : 6),
                  Text(
                    fingerpickGrid[i] != null ? _stringLabels[fingerpickGrid[i]!] : '·',
                    style: TextStyle(
                      fontSize: fingerpickGrid[i] != null ? 18 : 14,
                      fontWeight: fingerpickGrid[i] != null ? FontWeight.w600 : FontWeight.normal,
                      color: i == slot
                          ? cs.primary
                          : (fingerpickGrid[i] != null ? cs.onSurfaceVariant : cs.outline.withValues(alpha: 0.4)),
                    ),
                  ),
                ],
              ],
            )
          else
            // 扫弦:↓/↑/·
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < strumGrid.length; i++) ...[
                  if (i > 0) SizedBox(width: i.isEven ? 14 : 6),
                  if (strumGrid[i] == StrumDir.rest)
                    Text('·', style: TextStyle(fontSize: 14, color: cs.outline.withValues(alpha: 0.4)))
                  else
                    Text(
                      strumGrid[i] == StrumDir.down ? '↓' : '↑',
                      style: TextStyle(fontSize: 20, color: i == slot ? cs.primary : cs.outline),
                    ),
                ],
              ],
            ),
          const SizedBox(height: 4),
          // 信息行
          Text(
            countInNumber > 0
                ? '预备拍 · 准备从「${lineChords.isNotEmpty ? lineChords.first : '—'}」开始'
                : isFp
                    ? '第 ${slot ~/ 2 + 1} / $beatsPerChord 拍 · 拨${_stringLabels[fingerpickGrid.isNotEmpty && slot < fingerpickGrid.length && fingerpickGrid[slot] != null ? fingerpickGrid[slot]! : 3]}弦 · 下一个: $nextChord'
                    : '第 ${slot ~/ 2 + 1} / $beatsPerChord 拍  ·  下一个: $nextChord',
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          // 调速行
          Row(
            children: [
              IconButton(
                onPressed: canPlay ? onTogglePlay : null,
                tooltip: isPlaying ? '暂停' : '开始打拍',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                style: IconButton.styleFrom(
                  foregroundColor: cs.primary,
                  disabledForegroundColor: cs.onSurfaceVariant.withValues(alpha: 0.4),
                ),
              ),
              const SizedBox(width: 4),
              // 扫弦声/奏法开关
              IconButton(
                onPressed: onToggleStrumSound,
                tooltip: strumSoundOn
                    ? '${isFp ? "指弹声" : "扫弦声"}:开 · 按奏法播真声(点关)'
                    : '${isFp ? "指弹声" : "扫弦声"}:关 · 只剩节拍器嗒声(点开)',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: Icon(strumSoundOn ? Icons.graphic_eq : Icons.volume_off),
                style: IconButton.styleFrom(
                  foregroundColor: strumSoundOn ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: onToggleRamp,
                tooltip: rampOn ? '自动提速:开 · 每遍+3、到原速停(点关)' : '自动提速:关 · 每遍+3、到原速停(点开)',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: const Icon(Icons.trending_up_rounded),
                style: IconButton.styleFrom(
                  foregroundColor: rampOn ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: () => _showSoundPicker(context),
                tooltip: '节拍器音色: ${_soundLabel(metronomeSound)}',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: const Icon(Icons.speaker, size: 20),
                style: IconButton.styleFrom(
                  foregroundColor: metronomeSound != 'click' ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: onToggleFullscreen,
                tooltip: fullscreen ? '退出全屏' : '全屏练习',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: Icon(fullscreen ? Icons.fullscreen_exit : Icons.fullscreen, size: 20),
                style: IconButton.styleFrom(
                  foregroundColor: fullscreen ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 4),
              Text('调速', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
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
                child: Text('$tempo BPM', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showSoundPicker(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('节拍器音色'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final s in metronomeSoundNames)
                ListTile(
                  title: Text(_soundLabel(s)),
                  leading: Icon(
                    metronomeSound == s ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: metronomeSound == s ? Theme.of(ctx).colorScheme.primary : null,
                  ),
                  onTap: () {
                    onMetronomeSoundChanged(s);
                    Navigator.pop(ctx);
                  },
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
          ],
        );
      },
    );
  }

  static String _soundLabel(String s) => switch (s) {
    'click' => '嗒声(默认)',
    'beep'  => '电子嘀',
    'wood'  => '木鱼',
    'rim'   => '鼓边',
    _       => s,
  };
}

/// 练习栏那一排里的和弦卡
class _ChordRefCard extends StatelessWidget {
  static const _currentScale = 1.0;
  static const _otherScale = 0.65;

  final String name;
  final bool isCurrent;
  final VoidCallback? onTap;

  const _ChordRefCard({required this.name, this.isCurrent = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final scale = isCurrent ? _currentScale : _otherScale;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
        decoration: BoxDecoration(
          color: isCurrent ? cs.primaryContainer.withValues(alpha: 0.55) : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isCurrent ? cs.primary : cs.outlineVariant,
            width: isCurrent ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(name,
              style: TextStyle(fontSize: isCurrent ? 15 : 12, fontWeight: FontWeight.bold, color: cs.primary)),
            chordShapes.containsKey(name)
                ? ChordDiagram(frets: chordShapes[name]!, scale: scale)
                : isCurrent
                    ? Text(name, style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: cs.primary))
                    : const SizedBox(height: 52),
          ],
        ),
      ),
    );
  }
}
