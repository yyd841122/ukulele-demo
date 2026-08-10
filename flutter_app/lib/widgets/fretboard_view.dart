// 指弹曲谱(TAB)绘制部件(第67步/第74步)。
// 画 4 条横弦线 + 品位数字 + 当前高亮圆点 + 小节号,像吉他指弹谱一样从左往右滚动(横版 TAB)。
// 第74步:加自动滚动(ScrollController)、小节号标签、当前小节高亮。
//
// 弦序(从上到下):G(0)→C(1)→E(2)→A(3),跟 chordShapes frets 和 openTuning 顺序一致。
// 品位数字:0=空弦(显示 "0"),>0=数字,休止=不显示。
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

/// TAB 谱绘制器(CustomPainter):画 4 条横弦线 + 品位数字 + 小节线 + 小节号。
class _FretboardPainter extends CustomPainter {
  final List<TabNote> notes;      // 全部音符
  final int currentSlot;          // 当前高亮的槽位(-1=不高亮)
  final int slotsPerBar;          // 每小节几槽(给小节线+小节号用)
  final ColorScheme cs;

  // 布局常量
  static const double stringSpacing = 28.0;
  static const double slotWidth = 36.0;
  static const double topMargin = 20.0;      // 加高给小节号
  static const double leftMargin = 30.0;     // 左侧留白(小节号)
  static const double fontSize = 16.0;

  _FretboardPainter({
    required this.notes,
    required this.currentSlot,
    required this.slotsPerBar,
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
      paint.strokeWidth = s == 3 ? 1.5 : 1.0;
      canvas.drawLine(
        Offset(leftMargin, y),
        Offset(leftMargin + notes.length * slotWidth, y),
        paint,
      );
    }

    // --- 当前小节高亮底色 ---
    if (slotsPerBar > 0 && currentSlot >= 0) {
      final barIdx = currentSlot ~/ slotsPerBar;
      final barStart = barIdx * slotsPerBar;
      final barEnd = (barStart + slotsPerBar).clamp(0, notes.length);
      final fillPaint = Paint()
        ..color = cs.primaryContainer.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill;
      canvas.drawRect(
        Rect.fromLTRB(
          leftMargin + barStart * slotWidth,
          topMargin - 4,
          leftMargin + barEnd * slotWidth,
          topMargin + 3 * stringSpacing + 4,
        ),
        fillPaint,
      );
    }

    // --- 弦标签(左侧) ---
    final labelText = ui.TextStyle(
      color: ui.Color.fromARGB(cs.onSurfaceVariant.alpha, cs.onSurfaceVariant.red, cs.onSurfaceVariant.green, cs.onSurfaceVariant.blue),
      fontSize: 12,
      fontWeight: ui.FontWeight.w600,
    );
    for (var s = 0; s < 4; s++) {
      final lb = ['G', 'C', 'E', 'A'][s];
      final builder = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: ui.TextAlign.center))
        ..pushStyle(labelText)
        ..addText(lb);
      final para = builder.build()..layout(const ui.ParagraphConstraints(width: 20));
      canvas.drawParagraph(para, Offset(0, topMargin + s * stringSpacing - 7));
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
      final y = topMargin + n.stringIndex * stringSpacing - 6;

      final isCurrent = i == currentSlot;
      final builder = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: ui.TextAlign.center))
        ..pushStyle(isCurrent ? highlightStyle : textStyle)
        ..addText('${n.fret}');
      final para = builder.build()..layout(const ui.ParagraphConstraints(width: slotWidth));
      canvas.drawParagraph(para, Offset(x - slotWidth / 2, y));

      // 当前高亮圆点
      if (isCurrent) {
        final dotPaint = Paint()..color = cs.primary..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(x, topMargin + n.stringIndex * stringSpacing), 5, dotPaint);
      }
    }

    // --- 小节线 + 小节号 ---
    final barPaint = Paint()..color = cs.outlineVariant..strokeWidth = 1.5;
    final barNumStyle = ui.TextStyle(
      color: ui.Color.fromARGB(cs.outline.alpha, cs.outline.red, cs.outline.green, cs.outline.blue),
      fontSize: 10,
    );
    for (var bar = 1; bar * slotsPerBar < notes.length; bar++) {
      final x = leftMargin + bar * slotsPerBar * slotWidth;
      canvas.drawLine(Offset(x, topMargin - 4), Offset(x, topMargin + 3 * stringSpacing + 4), barPaint);
      // 小节号
      final nb = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: ui.TextAlign.center))
        ..pushStyle(barNumStyle)
        ..addText('$bar');
      final np = nb.build()..layout(const ui.ParagraphConstraints(width: 30));
      canvas.drawParagraph(np, Offset(x - 15, 0));
    }
  }

  @override
  bool shouldRepaint(covariant _FretboardPainter old) {
    return old.currentSlot != currentSlot || old.notes != notes;
  }
}

/// TAB 谱视图:横向滚动的指弹谱。第74步:加 ScrollController 自动滚动。
class TablatureView extends StatefulWidget {
  final List<TabNote> notes;
  final int currentSlot;
  final int slotsPerBar; // 每小节几槽(画小节线+小节号)

  const TablatureView({
    super.key,
    required this.notes,
    required this.currentSlot,
    required this.slotsPerBar,
  });

  @override
  State<TablatureView> createState() => _TablatureViewState();
}

class _TablatureViewState extends State<TablatureView> {
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void didUpdateWidget(covariant TablatureView old) {
    super.didUpdateWidget(old);
    if (widget.currentSlot != old.currentSlot && widget.currentSlot >= 0 && widget.notes.isNotEmpty) {
      _scrollToSlot();
    }
  }

  void _scrollToSlot() {
    final targetX = _FretboardPainter.leftMargin +
        widget.currentSlot * _FretboardPainter.slotWidth -
        60; // 左偏移让当前音符在可视区内
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        targetX.clamp(0.0, _scrollCtrl.position.maxScrollExtent),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final totalWidth = _FretboardPainter.leftMargin +
        widget.notes.length * _FretboardPainter.slotWidth + 20;
    final height = _FretboardPainter.topMargin + 3 * _FretboardPainter.stringSpacing + 32;

    return Container(
      height: height,
      color: cs.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        controller: _scrollCtrl,
        child: SizedBox(
          width: totalWidth > 0 ? totalWidth : 100,
          height: height,
          child: CustomPaint(
            painter: _FretboardPainter(
              notes: widget.notes,
              currentSlot: widget.currentSlot,
              slotsPerBar: widget.slotsPerBar,
              cs: cs,
            ),
          ),
        ),
      ),
    );
  }
}
