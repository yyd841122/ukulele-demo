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
}
