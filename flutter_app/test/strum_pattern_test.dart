// 扫弦节奏型(patternsFor)测试:锁住每个节奏型的网格形状不变量。
// 节奏型的 grid(下/上/休止在 8 分槽上的排布)直接决定「↓↑ 那排怎么高亮 + 扫弦声怎么响」,
// 排布错了节奏就变味。这里把每个节奏型的 4 拍网格钉死,以后改 patternsFor 不小心挪了槽位会立刻红。
import 'package:flutter_test/flutter_test.dart';
import 'package:ukulele_demo/models.dart';

// 辅助:把 grid(List<StrumDir>)压成可读字符串('D'/'U'/'-'),测试期望值更好读。
String _gridText(List<StrumDir> g) => g.map((d) {
      switch (d) {
        case StrumDir.down:
          return 'D';
        case StrumDir.up:
          return 'U';
        case StrumDir.rest:
          return '-';
      }
    }).join('');

void main() {
  group('patternsFor · 4 拍歌(8 槽)节奏型网格', () {
    final pats = patternsFor(4);
    StrumPattern byName(String n) => pats.firstWhere((p) => p.name == n);

    test('4 拍歌给 8 个节奏型(全下/下上/慢扫 + 5 个招牌)', () {
      expect(pats.length, 8);
      expect(
        pats.map((p) => p.name).toList(),
        ['全下', '下上', '慢扫', '海岛', '民谣', '下下上', '摇滚', '雷鬼切分'],
      );
    });

    test('全下:D - D - D - D - (每正拍一下 = 4 下)', () {
      expect(_gridText(byName('全下').grid(4)), 'D-D-D-D-');
    });

    test('下上:D U D U D U D U (每 8 分一下)', () {
      expect(_gridText(byName('下上').grid(4)), 'DUDUDUDU');
    });

    test('慢扫:D - - - D - - - (只第 1、3 拍)', () {
      // 跟「全下」在 4 拍下同形(4 拍正好 2 个正拍对 2 个慢扫点);区别在 6/8 拍下才显现(见下组)。
      expect(_gridText(byName('慢扫').grid(4)), 'D---D---');
    });

    test('海岛:D - D U - U D U (招牌)', () {
      expect(_gridText(byName('海岛').grid(4)), 'D-DU-UDU');
    });

    test('民谣:D - D U U - D U', () {
      expect(_gridText(byName('民谣').grid(4)), 'D-DUU-DU');
    });

    test('下下上:D D U - D D U - (双下 + 切分空)', () {
      expect(_gridText(byName('下下上').grid(4)), 'DDU-DDU-');
    });

    test('摇滚:D - D U D U D U (密集连续)', () {
      expect(_gridText(byName('摇滚').grid(4)), 'D-DUDUDU');
    });

    test('雷鬼切分:D - - U D - - U (正拍下 + 反拍上)', () {
      expect(_gridText(byName('雷鬼切分').grid(4)), 'D--UD--U');
    });
  });

  group('patternsFor · 非 4 拍歌(只给动态生成的 3 个)', () {
    test('3 拍歌:只给 全下/下上/慢扫,不给招牌(避免 8 槽写死型被截断)', () {
      final pats = patternsFor(3);
      expect(pats.length, 3);
      expect(pats.map((p) => p.name).toList(), ['全下', '下上', '慢扫']);
    });

    test('3 拍歌 全下/下上/慢扫 网格按 6 槽(3×2)生成、不越界', () {
      final pats = patternsFor(3);
      StrumPattern byName(String n) => pats.firstWhere((p) => p.name == n);
      expect(_gridText(byName('全下').grid(3)), 'D-D-D-');
      expect(_gridText(byName('下上').grid(3)), 'DUDUDU');
      // 慢扫步长 4,在 6 槽里只够 slot 0 一拍(下一拍 slot 4 在 3 拍里是第 3 拍正拍,也取到)。
      expect(_gridText(byName('慢扫').grid(3)), 'D---D-');
    });

    test('2 拍歌:也只给前 3 个,网格按 4 槽生成', () {
      final pats = patternsFor(2);
      expect(pats.length, 3);
      StrumPattern byName(String n) => pats.firstWhere((p) => p.name == n);
      expect(_gridText(byName('全下').grid(2)), 'D-D-');
      expect(_gridText(byName('慢扫').grid(2)), 'D---');
    });

    test('6 拍歌:慢扫体现区别——全下给 6 下,慢扫只给 3 下(0/4/8)', () {
      // 这正是「慢扫」独立存在的意义:非 4 拍下它比「全下」明显更疏。
      final pats = patternsFor(6);
      StrumPattern byName(String n) => pats.firstWhere((p) => p.name == n);
      expect(_gridText(byName('全下').grid(6)), 'D-D-D-D-D-D-'); // 每拍一下 = 6 下
      expect(_gridText(byName('慢扫').grid(6)), 'D---D---D---'); // 每 4 槽一下 = 3 下
    });
  });

  group('patternsFor · 网格长度与兜底', () {
    test('grid 长度恒 = beatsPerChord×2', () {
      for (final bpc in [2, 3, 4, 6, 8]) {
        for (final p in patternsFor(bpc)) {
          expect(p.grid(bpc).length, bpc * 2,
              reason: '${p.name} grid 长度应等于 beatsPerChord×2');
        }
      }
    });

    test('每个节奏型第一槽(第1拍正拍)都有一下下扫:起步稳、跟节拍器对得上', () {
      // 所有现有节奏型槽 0 都是 down:全下/下上/慢扫/海岛/民谣/下下上/摇滚/雷鬼切分 概莫能外。
      for (final bpc in [2, 3, 4, 6, 8]) {
        for (final p in patternsFor(bpc)) {
          expect(p.grid(bpc)[0], StrumDir.down,
              reason: '${p.name} 第1拍正拍应是下扫(down)');
        }
      }
    });

    test('所有扫弦槽位都在 [0, beatsPerChord×2) 内(防越界写法回归)', () {
      for (final bpc in [2, 3, 4, 6, 8]) {
        for (final p in patternsFor(bpc)) {
          for (final s in p.strums) {
            expect(s.slot, inInclusiveRange(0, bpc * 2 - 1),
                reason: '${p.name} 的槽位 ${s.slot} 越界(bpc=$bpc)');
          }
        }
      }
    });
  });
}
