// 节奏型 patternsFor + 指弹 fingerpickPatternsFor 的无头测试。
// 锁「4 拍给全部 5 个、非 4 拍只给全下/下上、动态两个的槽数对」。
// 第59步:加指弹节奏型测试(8 个型、grid 长度对、任何拍都适用)。
import 'package:flutter_test/flutter_test.dart';

import 'package:ukulele_demo/models.dart';

void main() {
  group('patternsFor 按拍数给不同选项', () {
    test('4 拍:全下/下上/海岛/民谣/摇滚 共 5 个', () {
      final p = patternsFor(4);
      expect(p.map((e) => e.name), ['全下', '下上', '海岛', '民谣', '摇滚']);
    });

    test('非 4 拍(3 拍华尔兹):只给全下/下上(招牌节奏藏掉,免截断)', () {
      final p = patternsFor(3);
      expect(p.map((e) => e.name), ['全下', '下上']);
    });

    test('非 4 拍(2 / 6 / 8):同样只给全下/下上', () {
      expect(patternsFor(2).map((e) => e.name), ['全下', '下上']);
      expect(patternsFor(6).map((e) => e.name), ['全下', '下上']);
      expect(patternsFor(8).map((e) => e.name), ['全下', '下上']);
    });
  });

  group('全下 / 下上 按拍数动态生成(grid 任何拍数都正常)', () {
    test('3 拍全下:3 个正拍下扫(6 槽里偶数槽)', () {
      final g = patternsFor(3).first.grid(3); // 全下
      expect(g.length, 6); // 3 拍 × 2 槽
      expect(g, [StrumDir.down, StrumDir.rest, StrumDir.down, StrumDir.rest, StrumDir.down, StrumDir.rest]);
    });

    test('3 拍下上:6 槽全满(偶下奇上)', () {
      final g = patternsFor(3)[1].grid(3); // 下上
      expect(g.length, 6);
      expect(g, [StrumDir.down, StrumDir.up, StrumDir.down, StrumDir.up, StrumDir.down, StrumDir.up]);
    });
  });

  group('fingerpickPatternsFor', () {
    test('4 拍歌:返回 8 个常见指弹型', () {
      final fps = fingerpickPatternsFor(4);
      expect(fps.length, 8);
      expect(fps.map((e) => e.name), [
        '4321 琶音',
        '4323 织体',
        '4231 下行',
        '3121 上行',
        '八拍琶音',
        '拇指节奏',
        '全下拨',
        '根音琶音',
      ]);
    });

    test('grid 长度 = beatsPerChord × 2', () {
      for (final bpc in [2, 3, 4, 6, 8]) {
        for (final fp in fingerpickPatternsFor(bpc)) {
          expect(fp.grid(bpc).length, bpc * 2);
        }
      }
    });

    test('任何拍数都返回 8 个型(动态适配)', () {
      for (final bpc in [2, 3, 6, 8]) {
        expect(fingerpickPatternsFor(bpc).length, 8);
      }
    });

    test('全下拨:只有正拍拨 G 弦(偶数槽=0,奇数槽=null)', () {
      final fp = fingerpickPatternsFor(4).firstWhere((f) => f.name == '全下拨');
      final g = fp.grid(4);
      expect(g.length, 8);
      for (var s = 0; s < 8; s++) {
        if (s.isEven) {
          expect(g[s], 0); // G 弦(stringIndex 0)
        } else {
          expect(g[s], isNull);
        }
      }
    });

    test('4321 琶音:物理 4-3-2-1 = stringIndex 0-1-2-3(G-C-E-A) 循环', () {
      final fp = fingerpickPatternsFor(4).firstWhere((f) => f.name == '4321 琶音');
      final g = fp.grid(4);
      expect(g.length, 8);
      expect(g[0], 0); // G
      expect(g[1], 1); // C
      expect(g[2], 2); // E
      expect(g[3], 3); // A
      expect(g[4], 0); // G (第二组)
      expect(g[5], 1);
      expect(g[6], 2);
      expect(g[7], 3);
    });
  });
}
