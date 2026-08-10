// 节奏型 patternsFor 的无头测试。锁「4 拍给全部 5 个、非 4 拍只给全下/下上、动态两个的槽数对」。
// 第51步:非 4 拍歌不再返回海岛/民谣/摇滚(它们按 8 槽写死会截断 / 不合乐理)。
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
}
