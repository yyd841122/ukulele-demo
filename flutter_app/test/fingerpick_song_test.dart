// 指弹曲谱数据结构测试(第78步):锁住节奏不变量。
// 每首曲子每小节的 duration 总和必须 = beatsPerBar × 4(16 分 tick 数,4/4 拍 = 16)。
// 这个不变量破了,播放节奏就会错——之前小星星每小节塞 8 个四分音符(=32 tick)就是这个 bug。
import 'package:flutter_test/flutter_test.dart';
import 'package:ukulele_demo/models.dart';

void main() {
  group('指弹曲谱小节时值不变量', () {
    for (final fSong in builtinFingerpickSongs) {
      test('${fSong.title}: 每小节 duration 总和 = ${fSong.beatsPerBar * 4} tick', () {
        for (var b = 0; b < fSong.bars.length; b++) {
          final sum = fSong.bars[b].slots.fold<int>(0, (s, slot) => s + slot.duration);
          expect(sum, fSong.beatsPerBar * 4,
              reason: '${fSong.title} 第 ${b + 1} 小节时值 $sum ≠ ${fSong.beatsPerBar * 4}(拍数×4)');
        }
      });
    }
  });

  group('小星星', () {
    final star = builtinFingerpickSongs.firstWhere((s) => s.title.contains('小星星'));

    test('12 小节', () {
      expect(star.bars.length, 12);
    });

    test('flatSlots 长度 = 各小节 slot 数之和', () {
      final expected = star.bars.fold<int>(0, (s, b) => s + b.slots.length);
      expect(star.flatSlots.length, expected);
    });

    test('第 1 小节 C C G G(弦1空×2 + 弦0空×2,四分音符)', () {
      final b = star.bars[0];
      expect(b.slots.length, 4);
      expect(b.slots[0].stringIndex, 1); // C 弦
      expect(b.slots[0].fret, 0);
      expect(b.slots[0].duration, 4);   // 四分
      expect(b.slots[2].stringIndex, 0); // G 弦
      expect(b.slots[2].fret, 0);
    });

    test('第 2 小节 A A G-(二分音符 duration=8)', () {
      final b = star.bars[1];
      expect(b.slots.length, 3);
      expect(b.slots[2].stringIndex, 0); // G 弦
      expect(b.slots[2].duration, 8);    // 二分
    });
  });

  group('flatSlots 拍扁一致', () {
    for (final fSong in builtinFingerpickSongs) {
      test('${fSong.title}: flatSlots 顺序 = 按 bar 顺序拼接', () {
        final manual = <FingerpickSlot>[];
        for (final b in fSong.bars) {
          manual.addAll(b.slots);
        }
        expect(fSong.flatSlots, manual);
      });
    }
  });

  // —— 第16步:两首 PD 儿歌指弹的旋律骨架(锁住标志性音,防误改 + 让"扒对了"可无头验证)——
  // 旋律音用 (stringIndex, fret) 对表示;时值另由上面的"每小节=16tick"守卫覆盖。
  group('划小船 / 老麦克唐纳 旋律骨架', () {
    final row = builtinFingerpickSongs.firstWhere((s) => s.title.contains('划小船'));
    final mac = builtinFingerpickSongs.firstWhere((s) => s.title.contains('老麦克唐纳'));

    // (弦,品) 对的简写,期望序列更好读。stringIndex 可空(休止符 fpr 没弦),故用 int?。
    List<(int?, int)> _melody(FingerpickSong s) =>
        s.flatSlots.map((slot) => (slot.stringIndex, slot.fret)).toList();

    test('划小船:do re mi do 开头(1,0)(1,2)(2,0)(1,0)', () {
      expect(_melody(row).sublist(0, 4), [(1, 0), (1, 2), (2, 0), (1, 0)]);
    });

    test('划小船:第3小节切分 sol la sol fa(0,0)(3,0)(0,0)(2,1)', () {
      // 第3小节4个八分音 sol-la-sol-fa 后接 mi-do(四分)。
      final b3 = row.bars[2].slots;
      expect((b3[0].stringIndex, b3[0].fret), (0, 0)); // sol
      expect((b3[1].stringIndex, b3[1].fret), (3, 0)); // la
      expect((b3[2].stringIndex, b3[2].fret), (0, 0)); // sol
      expect((b3[3].stringIndex, b3[3].fret), (2, 1)); // fa
    });

    test('老麦克唐纳:E-I-E-I-O 段 = mi do mi do sol(2,0)(3,3)(2,0)(3,3)(0,0)', () {
      // 第3小节是 E-I-E-I-O:八分 mi-do'-mi-do' + 二分 sol。
      final b3 = mac.bars[2].slots;
      expect((b3[0].stringIndex, b3[0].fret), (2, 0)); // mi
      expect((b3[1].stringIndex, b3[1].fret), (3, 3)); // do'
      expect((b3[2].stringIndex, b3[2].fret), (2, 0)); // mi
      expect((b3[3].stringIndex, b3[3].fret), (3, 3)); // do'
      expect((b3[4].stringIndex, b3[4].fret), (0, 0)); // sol(二分收)
    });

    test('两首都是 4/4(beatsPerBar=4)、全在 0-3 品(新手够得到)', () {
      for (final s in [row, mac]) {
        expect(s.beatsPerBar, 4);
        for (final slot in s.flatSlots) {
          expect(slot.fret, inInclusiveRange(0, 3),
              reason: '${s.title} 用到 ${slot.fret} 品,超出新手 0-3 品舒适区');
        }
      }
    });
  });
}
