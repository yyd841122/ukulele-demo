// 琶音拨弦型映射测试:锁住 arpStringAt 的拨弦顺序不变量。
// 这个映射错了,4321/4323 就会拨错弦(或拨空),是琶音页的核心不变量。
import 'package:flutter_test/flutter_test.dart';
import 'package:ukulele_demo/models.dart';

void main() {
  group('arpStringAt 拨弦顺序', () {
    final p4321 = builtinArpPatterns.firstWhere((p) => p.name.contains('4321'));
    final p4323 = builtinArpPatterns.firstWhere((p) => p.name.contains('4323'));

    test('4321 琶音(一拍一音):4 拍和弦一小节 = G·C·E·A,后半拍空', () {
      // slot 0..7(半拍槽):偶数槽拨,奇数槽空(让上一音延续)。
      const expected = [0, null, 1, null, 2, null, 3, null];
      for (var slot = 0; slot < 8; slot++) {
        expect(arpStringAt(p4321, 4, slot), expected[slot],
            reason: '4321 slot $slot 期望 ${expected[slot]}');
      }
    });

    test('4323 织体(八分):4 拍和弦一小节 = G C E C G C E C,两遍循环', () {
      const expected = [0, 1, 2, 1, 0, 1, 2, 1];
      for (var slot = 0; slot < 8; slot++) {
        expect(arpStringAt(p4323, 4, slot), expected[slot],
            reason: '4323 slot $slot 期望 ${expected[slot]}');
      }
    });

    test('每个和弦第一拍(slot 0)恒为拨弦型第 0 根弦(低音 G)', () {
      for (final p in builtinArpPatterns) {
        expect(arpStringAt(p, 4, 0), p.strings[0],
            reason: '${p.name} 第一拍应落在 strings[0]=${p.strings[0]}');
      }
    });

    test('3 拍和弦(bpc=3)按拍截断、不越界', () {
      // 4321 在 3 拍下:G·C·E(slot 0/2/4),第 4 音到不了(slot 6 已是下一和弦)。
      final r = [for (var s = 0; s < 6; s++) arpStringAt(p4321, 3, s)];
      expect(r, [0, null, 1, null, 2, null]);
      // 4323 在 3 拍下:0..5 = G C E C G C,正常循环不越界。
      final r2 = [for (var s = 0; s < 6; s++) arpStringAt(p4323, 3, s)];
      expect(r2, [0, 1, 2, 1, 0, 1]);
    });

    test('负 slot 返回 null(防越界兜底)', () {
      expect(arpStringAt(p4321, 4, -1), isNull);
    });
  });

  group('内置琶音数据合法性', () {
    test('所有拨弦型 stringIndex ∈ 0..3、notesPerBeat ∈ {1,2}', () {
      for (final p in builtinArpPatterns) {
        expect(p.strings.isNotEmpty, true);
        for (final s in p.strings) {
          expect(s, inInclusiveRange(0, 3), reason: '${p.name} 弦号 $s 越界(应 0..3)');
        }
        expect(p.notesPerBeat, isIn([1, 2]), reason: '${p.name} notesPerBeat 应为 1 或 2');
      }
    });

    test('每条练习的所有和弦都在 chordShapes 里(画图 + playString 都依赖)', () {
      for (final study in builtinArpStudies) {
        expect(study.chords.isNotEmpty, true, reason: '${study.title} 没有和弦');
        for (final c in study.chords) {
          expect(chordShapes.containsKey(c), true,
              reason: '${study.title} 的和弦「$c」不在 chordShapes 里,会画图崩 / playString 静音');
        }
      }
    });
  });
}
