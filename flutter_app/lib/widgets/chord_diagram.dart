// 和弦指法图部件:4 弦 × 4 品的网格 + 按弦点 / 空弦圈。
// 从 main.dart 拆出(第19步重构)。画法跟 Web 版 drawChord 一致。
import 'package:flutter/material.dart';

/// 和弦指法图:4 弦 × 4 品的网格,标出每根弦按第几品(实心点)、哪些是空弦(空心圈)。
/// frets 按 G C E A 顺序,0 = 空弦。scale 放大显示(坐标系固定 56×80)。复刻 Web 版 drawChord。
class ChordDiagram extends StatelessWidget {
  final List<int> frets;
  final double scale;

  const ChordDiagram({required this.frets, this.scale = 1, super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 56 * scale,
      height: 80 * scale,
      child: CustomPaint(
        painter: _ChordPainter(frets: frets, scale: scale, cs: cs),
      ),
    );
  }
}

class _ChordPainter extends CustomPainter {
  final List<int> frets;
  final double scale;
  final ColorScheme cs;

  const _ChordPainter({
    required this.frets,
    required this.scale,
    required this.cs,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(scale); // 之后用 56×80 的固定坐标画,scale 负责放大显示
    const left = 10.0, right = 46.0, top = 16.0, bottom = 72.0;
    const nStrings = 4, nFrets = 4;
    final dx = (right - left) / (nStrings - 1); // 弦间距 = 12
    final dy = (bottom - top) / nFrets; // 品间距 = 14

    final grid = Paint()
      ..color = cs.outline
      ..strokeWidth = 1;
    final nut = Paint()
      ..color = cs.onSurface
      ..strokeWidth = 3;
    final open = Paint()
      ..color = cs.onSurfaceVariant
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final pressed = Paint()
      ..color = cs.primary
      ..style = PaintingStyle.fill;

    // (1) 空弦圈:fret 0 的弦,在琴枕上方画空心圆
    for (var i = 0; i < nStrings; i++) {
      if (frets[i] == 0) {
        canvas.drawCircle(Offset(left + i * dx, 8), 3, open);
      }
    }
    // (2) 琴枕(nut):顶部粗线
    canvas.drawLine(Offset(left, top), Offset(right, top), nut);
    // (3) 品丝:4 条横线
    for (var f = 1; f <= nFrets; f++) {
      final y = top + f * dy;
      canvas.drawLine(Offset(left, y), Offset(right, y), grid);
    }
    // (4) 弦:4 根竖线
    for (var i = 0; i < nStrings; i++) {
      final x = left + i * dx;
      canvas.drawLine(Offset(x, top), Offset(x, bottom), grid);
    }
    // (5) 按弦点:fret>0 的弦,在对应品格中点画实心圆
    for (var i = 0; i < nStrings; i++) {
      if (frets[i] > 0) {
        final x = left + i * dx;
        final y = top + (frets[i] - 0.5) * dy;
        canvas.drawCircle(Offset(x, y), 5, pressed);
      }
    }
  }

  @override
  bool shouldRepaint(_ChordPainter old) =>
      old.frets != frets || old.scale != scale;
}
