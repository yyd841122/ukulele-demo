// 指弹曲谱(TAB)绘制部件(第67步/第74步/第78步重构)。
// 画 4 条横弦线 + 品位数字(按时值宽度)+ 小节线 + 当前高亮圆点。
// 第78步:音宽 ∝ duration(节奏可视化),小节线按 barStartSlots 真实边界,自动滚动。
//
// 弦序(从上到下):G(0)→C(1)→E(2)→A(3)。
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// TAB 谱上的一个音符:哪根弦、第几品、时值多少(16 分音符为单位)。
class TabNote {
  final int stringIndex; // 0=G, 1=C, 2=E, 3=A
  final int fret;        // 品位(0=空弦)
  final bool isRest;     // 休止
  final int duration;    // 时值(16 分音符数):1=16分,2=8分,4=4分,8=2分

  const TabNote({required this.stringIndex, required this.fret, this.isRest = false, this.duration = 1});
  const TabNote.rest({this.duration = 1}) : stringIndex = 0, fret = 0, isRest = true;
}

/// TAB 谱绘制器(CustomPainter)。
class _FretboardPainter extends CustomPainter {
  final List<TabNote> notes;
  final int currentSlot;       // 当前高亮的音(在 notes 里的下标,-1=不高亮)
  final List<int> barStarts;   // 每个小节的起始 slot 下标(画小节线用)
  final ColorScheme cs;

  // 布局常量
  static const double stringSpacing = 28.0;
  static const double unitWidth = 11.0;   // 一个 16 分音符的宽度(px)。四分音符=44px,二分=88px
  static const double topMargin = 20.0;   // 顶部留白(小节号)
  static const double leftMargin = 30.0;  // 左侧留白(弦标签)
  static const double fontSize = 15.0;

  _FretboardPainter({required this.notes, required this.currentSlot, required this.barStarts, required this.cs});

  /// 第 i 个音的水平起始 x(累计前面所有音的 duration)。
  double _xAt(int i) {
    var x = leftMargin;
    for (var k = 0; k < i && k < notes.length; k++) {
      x += (notes[k].duration <= 0 ? 1 : notes[k].duration) * unitWidth;
    }
    return x;
  }

  /// 整个谱的总宽度。
  static double totalLayoutWidth(List<TabNote> notes) {
    var w = leftMargin;
    for (final n in notes) {
      w += (n.duration <= 0 ? 1 : n.duration) * unitWidth;
    }
    return w + 20;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (notes.isEmpty) return;
    final totalWidth = totalLayoutWidth(notes);
    final bottomY = topMargin + 3 * stringSpacing;

    final paint = Paint()..style = PaintingStyle.stroke;

    // --- 当前小节高亮底色 ---
    int curBar = -1;
    if (currentSlot >= 0) {
      curBar = 0;
      for (var b = 0; b < barStarts.length; b++) {
        if (barStarts[b] <= currentSlot) curBar = b;
      }
    }
    if (curBar >= 0 && curBar < barStarts.length) {
      final barStartSlot = barStarts[curBar];
      final barEndSlot = curBar + 1 < barStarts.length ? barStarts[curBar + 1] : notes.length;
      final x1 = _xAt(barStartSlot);
      final x2 = _xAt(barEndSlot);
      final fillPaint = Paint()..color = cs.primaryContainer.withValues(alpha: 0.3)..style = PaintingStyle.fill;
      canvas.drawRect(Rect.fromLTRB(x1, topMargin - 6, x2, bottomY + 6), fillPaint);
    }

    // --- 画 4 条弦线 ---
    for (var s = 0; s < 4; s++) {
      final y = topMargin + s * stringSpacing;
      paint.color = s == 3 ? cs.outlineVariant : cs.outline.withValues(alpha: 0.3);
      paint.strokeWidth = s == 3 ? 1.5 : 1.0;
      canvas.drawLine(Offset(leftMargin, y), Offset(totalWidth, y), paint);
    }

    // --- 弦标签(左侧 G/C/E/A) ---
    final labelStyle = ui.TextStyle(
      color: cs.onSurfaceVariant,
      fontSize: 12, fontWeight: ui.FontWeight.w600,
    );
    for (var s = 0; s < 4; s++) {
      final lb = ['G', 'C', 'E', 'A'][s];
      final b = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: ui.TextAlign.center))..pushStyle(labelStyle)..addText(lb);
      final p = b.build()..layout(const ui.ParagraphConstraints(width: 20));
      canvas.drawParagraph(p, Offset(2, topMargin + s * stringSpacing - 7));
    }

    // --- 画品位数字(每个音居中在它占的宽度里) ---
    final normalStyle = ui.TextStyle(
      color: cs.onSurfaceVariant,
      fontSize: fontSize, fontWeight: ui.FontWeight.w600,
    );
    final hiStyle = ui.TextStyle(
      color: cs.primary,
      fontSize: fontSize, fontWeight: ui.FontWeight.bold,
    );
    for (var i = 0; i < notes.length; i++) {
      final n = notes[i];
      final dur = n.duration <= 0 ? 1 : n.duration;
      final noteW = dur * unitWidth;
      final cx = _xAt(i) + noteW / 2;
      final isCurrent = i == currentSlot;
      if (!n.isRest) {
        final y = topMargin + n.stringIndex * stringSpacing - 7;
        final b = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: ui.TextAlign.center))
          ..pushStyle(isCurrent ? hiStyle : normalStyle)
          ..addText('${n.fret}');
        final p = b.build()..layout(ui.ParagraphConstraints(width: noteW + 6));
        canvas.drawParagraph(p, Offset(cx - (noteW + 6) / 2, y));
      } else if (dur >= 4) {
        // 休止且时值≥4分:画一个短横线表示延长(像五线谱的休止/延音)
        final linePaint = Paint()..color = cs.outline.withValues(alpha: 0.5)..strokeWidth = 1.5;
        final y = topMargin + 1.5 * stringSpacing;
        canvas.drawLine(Offset(_xAt(i) + 4, y), Offset(_xAt(i) + noteW - 4, y), linePaint);
      }
      // 当前音:下方弦上画高亮圆点
      if (isCurrent && !n.isRest) {
        final dotPaint = Paint()..color = cs.primary..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(cx, topMargin + n.stringIndex * stringSpacing), 5, dotPaint);
      }
    }

    // --- 小节线 + 小节号(按 barStarts) ---
    final barPaint = Paint()..color = cs.outlineVariant..strokeWidth = 1.5;
    final barNumStyle = ui.TextStyle(
      color: cs.outline,
      fontSize: 10,
    );
    for (var b = 0; b <= barStarts.length; b++) {
      final slotIdx = b < barStarts.length ? barStarts[b] : notes.length;
      if (slotIdx <= 0 || slotIdx >= notes.length) continue;
      final x = _xAt(slotIdx);
      canvas.drawLine(Offset(x, topMargin - 6), Offset(x, bottomY + 6), barPaint);
      // 小节号标在小节线下方
      if (b > 0 && b < barStarts.length) {
        final nb = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: ui.TextAlign.center))
          ..pushStyle(barNumStyle)..addText('$b');
        final np = nb.build()..layout(const ui.ParagraphConstraints(width: 30));
        canvas.drawParagraph(np, Offset(x - 15, bottomY + 8));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FretboardPainter old) {
    return old.currentSlot != currentSlot || old.notes != notes || old.barStarts != barStarts;
  }
}

/// TAB 谱视图:横向滚动 + 自动滚到当前音。
class TablatureView extends StatefulWidget {
  final List<TabNote> notes;
  final int currentSlot;
  final List<int> barStarts; // 每小节起始 slot 下标

  const TablatureView({super.key, required this.notes, required this.currentSlot, required this.barStarts});

  @override
  State<TablatureView> createState() => _TablatureViewState();
}

class _TablatureViewState extends State<TablatureView> {
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void didUpdateWidget(covariant TablatureView old) {
    super.didUpdateWidget(old);
    if (widget.currentSlot != old.currentSlot && widget.currentSlot >= 0 && widget.notes.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSlot());
    }
  }

  void _scrollToSlot() {
    if (!_scrollCtrl.hasClients || widget.notes.isEmpty) return;
    var x = _FretboardPainter.leftMargin;
    for (var k = 0; k < widget.currentSlot && k < widget.notes.length; k++) {
      final d = widget.notes[k].duration <= 0 ? 1 : widget.notes[k].duration;
      x += d * _FretboardPainter.unitWidth;
    }
    final target = (x - 80).clamp(0.0, _scrollCtrl.position.maxScrollExtent);
    _scrollCtrl.animateTo(target, duration: const Duration(milliseconds: 120), curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final totalWidth = _FretboardPainter.totalLayoutWidth(widget.notes);
    final height = _FretboardPainter.topMargin + 3 * _FretboardPainter.stringSpacing + 34;

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
              barStarts: widget.barStarts,
              cs: cs,
            ),
          ),
        ),
      ),
    );
  }
}
