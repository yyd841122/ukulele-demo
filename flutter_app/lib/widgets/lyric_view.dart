// 歌词区的部件:段落标题、一行歌词(词单元 + 和弦贴片)、AB 循环徽标。
// 从 main.dart 拆出(第19步重构)。歌词按词渲染、和弦浮在词上方,逻辑跟拆分前一致。
import 'package:flutter/material.dart';

import '../models.dart';

/// AB 循环点的标记类型:不是标记 / A 点(起点)/ B 点(终点)。
/// 拆出 main.dart 时去掉下划线变 public——SongScreen 的 _markerForLine 算出来、传给 LineView 用。
enum AbMarker { none, a, b }

/// 段落标题(如"🎶 副歌")。
class SectionHeader extends StatelessWidget {
  final String name;

  const SectionHeader(this.name, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(
        name,
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 一行歌词:每个词一个单元,横向排开、自动换行。
/// 有和弦的词:上方浮和弦贴片;没和弦的词:纯文字(不留空、连贯)。
/// 所有词底部对齐(同一基线)。每个和弦词的单元至少和它的贴片一样宽,
/// 所以短词(如 "[C]I [G]watch" 里的 I)后面会自动多出间隙 → 和弦有地方放、不会叠、也不用错开。
/// 间隙不固定,由和弦宽度和词长决定(目标是练习弹奏:和弦该在哪、词就给哪腾地方)。
/// lineKey 定位自动滚动;isCurrentLine 时整行加底色;chordStart+currentChord 判断当前和弦;
/// marker / inRange 给 AB 循环画徽标和区间底色;onTap 点这行设 AB 循环点。
class LineView extends StatelessWidget {
  final Line line;
  final GlobalKey lineKey;
  final bool isCurrentLine;
  final int chordStart; // 这一行第 1 个和弦在全局 _flat 里的下标
  final int currentChord; // 当前全局和弦下标(_idx)
  final AbMarker marker; // 这行的 AB 标记(none/a/b)
  final bool inRange; // 这行在 AB 区间内吗(区间内的行加左边框、淡底色)
  final VoidCallback? onTap; // 点这行 → 设 AB 循环点

  const LineView({
    super.key,
    required this.line,
    required this.lineKey,
    required this.isCurrentLine,
    required this.chordStart,
    required this.currentChord,
    this.marker = AbMarker.none,
    this.inRange = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final units = parseWords(line.lyric);
    var localChord = 0; // 这一行里数到第几个和弦
    final children = <Widget>[];
    for (final u in units) {
      final isCurrent = u.hasChord && chordStart + localChord == currentChord;
      if (u.hasChord) localChord++;
      children.add(
        _WordUnitView(chord: u.chord, word: u.word, isCurrent: isCurrent),
      );
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        key: lineKey,
        padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
        decoration: BoxDecoration(
          color: isCurrentLine
              ? cs.primaryContainer.withValues(alpha: 0.3)
              : (inRange ? cs.primaryContainer.withValues(alpha: 0.12) : null),
          borderRadius: BorderRadius.circular(6),
          // 注意:不在区间内时 border 必须给 null,不能给 width:0 的边框——
          // "宽度0的细线边框 + borderRadius"会被 Flutter 断言拒掉(paint 时抛异常、疯狂刷错)。
          border: inRange
              ? Border(left: BorderSide(color: cs.primary, width: 3))
              : null,
        ),
        // 左边可能一个 AB 徽标,右边是歌词词单元(Wrap)。徽标顶对齐,词按基线排。
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (marker != AbMarker.none)
              Padding(
                padding: const EdgeInsets.only(top: 3, right: 6),
                child: _AbBadge(marker),
              ),
            Expanded(
              // Wrap:词单元横向排开、窄屏自动换行。crossAxisAlignment=end → 所有词同基线,
              // 和弦只浮在"有和弦的词"上方(没和弦的词不占和弦槽,连贯)。
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: 4,
                runSpacing: 2,
                children: children,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// AB 循环点的行徽标:一个小圆,写着 A 或 B。点在歌词行左边标出区间起止。
class _AbBadge extends StatelessWidget {
  final AbMarker marker;
  const _AbBadge(this.marker);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.primary,
        shape: BoxShape.circle,
      ),
      child: Text(
        marker == AbMarker.a ? 'A' : 'B',
        style: TextStyle(
          color: cs.onPrimary,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// 一个词单元:
/// - 有和弦 → Column[和弦贴片, 词]。Column 宽 = max(贴片宽, 词宽),所以贴片比词宽时
///   (如 "I" 配 C),单元被撑宽 → 它和下一个词之间自动多出间隙,和弦不挤不叠。
/// - 无和弦 → 纯词(Wrap 底对齐,和有和弦的词同一基线)。
class _WordUnitView extends StatelessWidget {
  final String? chord;
  final String word;
  final bool isCurrent;

  const _WordUnitView({this.chord, required this.word, this.isCurrent = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (chord == null) {
      return Text(word, style: theme.textTheme.bodyLarge);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _ChordChip(chord!, isCurrent: isCurrent, compact: true),
        const SizedBox(height: 3),
        Text(word, style: theme.textTheme.bodyLarge),
      ],
    );
  }
}

/// 单个和弦贴片:圆角小色块 + 和弦名。
/// isCurrent 时反色(主色实底 + 反色字)把"现在按这个"点出来。
/// compact=true 用更小的字号/内边距,给"和弦浮在歌词上方"那种紧凑贴片用。
class _ChordChip extends StatelessWidget {
  final String chord;
  final bool isCurrent;
  final bool compact;

  const _ChordChip(this.chord, {this.isCurrent = false, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 10,
        vertical: compact ? 1 : 4,
      ),
      decoration: BoxDecoration(
        color: isCurrent ? cs.primary : cs.primaryContainer,
        borderRadius: BorderRadius.circular(compact ? 5 : 8),
        border: Border.all(color: cs.primary, width: 1),
      ),
      child: Text(
        chord,
        style: TextStyle(
          color: isCurrent ? cs.onPrimary : cs.onPrimaryContainer,
          fontWeight: FontWeight.bold,
          fontSize: compact ? 12 : 14,
        ),
      ),
    );
  }
}
