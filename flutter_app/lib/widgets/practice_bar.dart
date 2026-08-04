// 顶部练习栏(吸顶)部件 + 里面那一排的和弦卡。
// 从 main.dart 拆出(第19步重构)。数据全是父级(SongScreen)算好传进来的,自己没状态。
import 'package:flutter/material.dart';

import '../models.dart';
import 'chord_diagram.dart';

/// 顶部练习栏(吸顶):一排和弦卡 =【当前这一行】的和弦,弹到哪个、那张就变大指法图并高亮,其余当小参考。
/// 下面:节奏型选择 + AB 状态 + 这一组扫到第几下(一排 ↓/↑)+ 信息行 + 调速滑块。
/// 数据全是父级算好传进来的;它自己没状态,只负责显示。对齐 Web 版 .panel。
class PracticeBar extends StatelessWidget {
  final List<String> lineChords; // 当前这一行的和弦(顺序、含重复)
  final int currentChordIndex; // 当前弹到这一行的第几个(0 起)
  final int slot; // 当前8分音符槽位(0 起,一组共 beatsPerChord×2 个)
  final int beatsPerChord; // 一组几拍
  final List<StrumDir> strumGrid; // 当前节奏型按槽位拍成的方向网格(长度 = beatsPerChord×2)
  final List<String> patternNames; // 可选节奏型的名字(给那一排选择芯片用)
  final int patternIndex; // 当前选第几个节奏型
  final ValueChanged<int> onPatternChanged; // 切节奏型时回调父级
  final bool abActive; // AB 循环区间设好了吗(没设就显示提示,设了显示状态 + ✕)
  final VoidCallback onClearAb; // 清除 AB 区间
  final int countInNumber; // 预备拍当前数到几(1..beatsPerChord);0 = 不在数预备拍
  final String nextChord; // 下一个和弦名
  final int tempo; // 当前速度(可调,实际在用的 BPM)
  final int minTempo; // 滑块最慢一档(约原速一半)
  final int maxTempo; // 滑块最快一档(原速)
  final ValueChanged<int> onTempoChanged; // 拖滑块时回调父级 _setTempo
  final bool isPlaying; // 现在在打拍吗(决定显示 ⏸ 还是 ▶)
  final bool canPlay; // 音频加载好了吗(没好就灰掉、按不动)
  final VoidCallback onTogglePlay; // 按一下 ▶/⏸
  final bool strumSoundOn; // 扫弦声开吗(播放时播真扫弦声 vs 只嗒声)
  final VoidCallback onToggleStrumSound; // 切扫弦声开关
  final bool rampOn; // 自动提速开吗(每遍+3 BPM、到原速停)
  final VoidCallback onToggleRamp; // 切自动提速开关
  final void Function(String chord)? onChordTap; // 点某个和弦卡 → 听这个和弦的扫弦声(可空)

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
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // 这一行的和弦卡:按行内顺序排,弹到第几个(currentChordIndex)那张就变大图高亮,其余小参考。
    // 第 1 张前面不留间距,之后每张前面塞 8px 间隙(Row 没有 spacing 参数,这是常见写法)。
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
          // 一排和弦卡:这首歌所有和弦各一张,弹到哪个、那张就自动变大图并高亮,其余当小参考。
          // 不再单独画大图——"现在弹哪个"由这一排里被放大的那张直接表达。横向可滚,和弦多也不撑爆。
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: refCards,
            ),
          ),
          const SizedBox(height: 6),
          // 节奏型选择:一排小芯片,点哪个用哪个。预备拍时也能选(提前挑好)。
          Wrap(
            spacing: 6,
            children: [
              for (var i = 0; i < patternNames.length; i++)
                ChoiceChip(
                  label: Text(
                    patternNames[i],
                    style: const TextStyle(fontSize: 12),
                  ),
                  selected: i == patternIndex,
                  onSelected: (_) => onPatternChanged(i),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          // AB 循环状态行:没设时给操作提示;设好后显示"循环中"+ ✕ 清除。
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: abActive
                ? Row(
                    children: [
                      Icon(Icons.repeat_rounded, size: 16, color: cs.primary),
                      const SizedBox(width: 4),
                      Text(
                        'AB 循环中',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: onClearAb,
                        tooltip: '清除 AB 区间',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        icon: const Icon(Icons.close_rounded, size: 18),
                        style: IconButton.styleFrom(
                          foregroundColor: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  )
                : Text(
                    '👆 点两行歌词设 AB 循环点(到 B 跳回 A 反复练)',
                    style: TextStyle(fontSize: 11, color: cs.outline),
                  ),
          ),
          const SizedBox(height: 4),
          // 扫弦型 / 预备拍数字(二选一):
          // 正式播放:按8分音符槽位画一排 ↓/↑/(·休止),当前槽用颜色高亮(不变大,免得整排跳动晕眼);正拍(偶数槽)前留宽缝,把"一拍两槽"归成一组,节奏一眼可读。
          // 预备拍(countInNumber>0):换成大字 1..N 倒计时,当前那拍高亮(跟旧版一致)。
          countInNumber > 0
              ? Row(
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
                            color: i + 1 == countInNumber
                                ? cs.primary
                                : cs.outline,
                          ),
                        ),
                      ),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < strumGrid.length; i++) ...[
                      if (i > 0) SizedBox(width: i.isEven ? 14 : 6),
                      if (strumGrid[i] == StrumDir.rest)
                        Text(
                          '·',
                          style: TextStyle(
                            fontSize: 14,
                            color: cs.outline.withValues(alpha: 0.4),
                          ),
                        )
                      else
                        Text(
                          strumGrid[i] == StrumDir.down ? '↓' : '↑',
                          // 只用颜色高亮当前那下,字号固定不变大——
                          // 每个↓轮着放大会让整排一直跳动,手机上看久了晕眼。
                          style: TextStyle(
                            fontSize: 20,
                            color: i == slot ? cs.primary : cs.outline,
                          ),
                        ),
                    ],
                  ],
                ),
          const SizedBox(height: 4),
          // 信息行:预备拍时提示"准备从哪个和弦开始";否则显示当前第几拍 + 下一个和弦。
          Text(
            countInNumber > 0
                ? '预备拍 · 准备从「${lineChords.isNotEmpty ? lineChords.first : '—'}」开始'
                : '第 ${slot ~/ 2 + 1} / $beatsPerChord 拍  ·  下一个: $nextChord',
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          // 调速行:最左 ▶/⏸ 小图标(节拍器总开关)+ "调速"字 + 中间滑块 + 右边实时 BPM。
          // ▶/⏸ 从右下大圆按钮挪到这里当小图标,免得歌长时挡住歌词。
          // clamp 是保险:万一 tempo 落在 [min,max] 外(理论上不会),Slider 会断言报错,钳一下就稳。
          Row(
            children: [
              IconButton(
                onPressed: canPlay ? onTogglePlay : null,
                tooltip: isPlaying ? '暂停' : '开始打拍',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
                style: IconButton.styleFrom(
                  foregroundColor: cs.primary,
                  disabledForegroundColor: cs.onSurfaceVariant.withValues(
                    alpha: 0.4,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // 扫弦声开关:开 = 播放时按节奏型播真扫弦声(代替嗒声);关 = 只剩节拍器嗒声。
              IconButton(
                onPressed: onToggleStrumSound,
                tooltip: strumSoundOn ? '扫弦声:开 · 按节奏型播真扫弦声(点关)' : '扫弦声:关 · 只剩节拍器嗒声(点开)',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: Icon(strumSoundOn ? Icons.graphic_eq : Icons.volume_off),
                style: IconButton.styleFrom(
                  foregroundColor:
                      strumSoundOn ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 4),
              // 自动提速开关:开 = 每过一遍 +3 BPM、到原速停(渐进提速练法);关 = 速度只手动调。
              IconButton(
                onPressed: onToggleRamp,
                tooltip: rampOn
                    ? '自动提速:开 · 每遍+3、到原速停(点关)'
                    : '自动提速:关 · 每遍+3、到原速停(点开)',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: const Icon(Icons.trending_up_rounded),
                style: IconButton.styleFrom(
                  foregroundColor: rampOn ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '调速',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
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
                child: Text(
                  '$tempo BPM',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 练习栏那一排里的和弦卡:和弦名(上)+ 指法图(下)。
/// isCurrent(现在弹的这个)时:指法图放大、字号变大 + 主色高亮边框/底色——一排里被放大的那张就是"现在弹哪个"。
/// 其余和弦用小一号指法图当参考。和弦在 chordShapes 里有数据就画图;没有(以后加了没录指法的)退回不崩。
class _ChordRefCard extends StatelessWidget {
  static const _currentScale = 1.0; // 当前和弦的大图
  static const _otherScale = 0.65; // 其余参考和弦的小图

  final String name;
  final bool isCurrent;
  final VoidCallback? onTap; // 点这个和弦卡 → 听它的扫弦声(播放中也能点,多声部叠着响)

  const _ChordRefCard({
    required this.name,
    this.isCurrent = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final scale = isCurrent ? _currentScale : _otherScale;
    // InkWell 包一层:点了有水波纹反馈(顺卡圆角裁)。onTap 为 null 时仍正常显示、只是不响应点。
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
        decoration: BoxDecoration(
          color: isCurrent
              ? cs.primaryContainer.withValues(alpha: 0.55)
              : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isCurrent ? cs.primary : cs.outlineVariant,
            width: isCurrent ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              style: TextStyle(
                fontSize: isCurrent ? 15 : 12,
                fontWeight: FontWeight.bold,
                color: cs.primary,
              ),
            ),
            // 有指法数据就画图(当前和弦用大图、其余小图);没数据时:当前和弦退回大字母、其余占位保高。
            chordShapes.containsKey(name)
                ? ChordDiagram(frets: chordShapes[name]!, scale: scale)
                : isCurrent
                ? Text(
                    name,
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: cs.primary,
                    ),
                  )
                : const SizedBox(height: 52),
          ],
        ),
      ),
    );
  }
}
