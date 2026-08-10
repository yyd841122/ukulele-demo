// 指弹曲谱(TAB)绘制部件(第67步)。
// 画 4 条横弦线 + 品位数字 + 当前高亮圆点,像吉他指弹谱一样从左往右滚动(横版 TAB)。
//
// 弦序(从上到下):G(0)→C(1)→E(2)→A(3),跟 chordShapes frets 和 openTuning 顺序一致。
// 品位数字:0=空弦(显示 "0"),>0=数字,休止=不显示。
// 当前弹到的槽位:数字主色高亮 + 下方小圆点。
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// TAB 谱上的一个音符:哪根弦、第几品。
class TabNote {
  final int stringIndex; // 0=G, 1=C, 2=E, 3=A
  final int fret;        // 品位(0=空弦)
  final bool isRest;     // 休止

  const TabNote({required this.stringIndex, required this.fret, this.isRest = false});
  const TabNote.rest() : stringIndex = 0, fret = 0, isRest = true;
}

/// TAB 谱绘制器(CustomPainter):画 4 条横弦线 + 品位数字 + 当前高亮圆点。
class _FretboardPainter extends CustomPainter {
  final List<TabNote> notes;      // 全部音符
  final int currentSlot;          // 当前高亮的槽位(-1=不高亮)
  final int beatsPerChord;        // 每组几拍(画小节线用)
  final ColorScheme cs;           // 主题色

  // 布局常量
  static const double stringSpacing = 28.0;  // 弦与弦的垂直间距
  static const double slotWidth = 36.0;      // 每个槽位的水平宽度
  static const double topMargin = 12.0;      // 顶部留白
  static const double leftMargin = 20.0;     // 左侧留白(给弦标签)
  static const double fontSize = 16.0;       // 品位数字字号

  _FretboardPainter({
    required this.notes,
    required this.currentSlot,
    required this.beatsPerChord,
    required this.cs,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (notes.isEmpty) return;

    final paint = Paint()..style = PaintingStyle.stroke;

    // --- 画 4 条弦线 ---
    for (var s = 0; s < 4; s++) {
      final y = topMargin + s * stringSpacing;
      paint.color = s == 3 ? cs.outlineVariant : cs.outline.withValues(alpha: 0.3);
      paint.strokeWidth = s == 3 ? 1.5 : 1.0; // A 弦稍微粗一点
      canvas.drawLine(
        Offset(leftMargin, y),
        Offset(leftMargin + notes.length * slotWidth, y),
        paint,
      );
    }

    // --- 画品位数字 ---
    final onSurf = cs.onSurfaceVariant;
    final prim = cs.primary;
    final textStyle = ui.TextStyle(
      color: ui.Color.fromARGB(onSurf.alpha, onSurf.red, onSurf.green, onSurf.blue),
      fontSize: fontSize,
      fontWeight: ui.FontWeight.w600,
    );
    final highlightStyle = ui.TextStyle(
      color: ui.Color.fromARGB(prim.alpha, prim.red, prim.green, prim.blue),
      fontSize: fontSize,
      fontWeight: ui.FontWeight.bold,
    );

    for (var i = 0; i < notes.length; i++) {
      final n = notes[i];
      if (n.isRest) continue;

      final x = leftMargin + i * slotWidth + slotWidth / 2;
      // 数字的中心放在弦线上方一点点(避免跟线重叠)
      final y = topMargin + n.stringIndex * stringSpacing - 6;

      final isCurrent = i == currentSlot;
      final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
        textAlign: ui.TextAlign.center,
      ))
        ..pushStyle(isCurrent ? highlightStyle : textStyle)
        ..addText('${n.fret}');
      final para = builder.build()..layout(const ui.ParagraphConstraints(width: slotWidth));
      canvas.drawParagraph(para, Offset(x - slotWidth / 2, y));

      // 当前高亮:数字下方画一个小圆点
      if (isCurrent) {
        final dotPaint = Paint()
          ..color = cs.primary
          ..style = PaintingStyle.fill;
        canvas.drawCircle(
          Offset(x, topMargin + n.stringIndex * stringSpacing),
          5,
          dotPaint,
        );
      }
    }

    // --- 画小节线(每 beatsPerChord 拍) ---
    final paintBar = Paint()
      ..color = cs.outlineVariant
      ..strokeWidth = 1.5;
    for (var bar = 1; bar * beatsPerChord * 2 < notes.length; bar++) {
      final x = leftMargin + bar * beatsPerChord * 2 * slotWidth;
      canvas.drawLine(
        Offset(x, topMargin - 4),
        Offset(x, topMargin + 3 * stringSpacing + 4),
        paintBar,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FretboardPainter old) {
    return old.currentSlot != currentSlot || old.notes != notes;
  }
}

/// TAB 谱视图:横向滚动的指弹谱。
class TablatureView extends StatelessWidget {
  final List<TabNote> notes;
  final int currentSlot;
  final int beatsPerChord;

  const TablatureView({
    super.key,
    required this.notes,
    required this.currentSlot,
    required this.beatsPerChord,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final totalWidth = _FretboardPainter.leftMargin + notes.length * _FretboardPainter.slotWidth + 20;
    final height = _FretboardPainter.topMargin + 3 * _FretboardPainter.stringSpacing + 32;

    return Container(
      height: height,
      color: cs.surface,
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: totalWidth,
              height: height,
              child: CustomPaint(
                painter: _FretboardPainter(
                  notes: notes,
                  currentSlot: currentSlot,
                  beatsPerChord: beatsPerChord,
                  cs: cs,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
