// 练习日历纯函数(practiceDayKey / currentStreak)的无头单元测试。
// 不连手机(flutter test):锁"连续打卡天数"的几种边界——连练、断了、今天还没练、乱序、空。
// 把 streak 逻辑从统计页里抽成纯函数(不依赖系统时钟 / setState,today 由调用方传),
// 就是为了这里能传固定的 today 直接、稳定地测,不被 DateTime.now 左右。
import 'package:flutter_test/flutter_test.dart';

import 'package:ukulele_demo/models.dart';

void main() {
  group('practiceDayKey 日期键', () {
    test('折成 yyyy-MM-dd(零填充)', () {
      expect(practiceDayKey(DateTime(2026, 8, 6)), '2026-08-06');
      expect(practiceDayKey(DateTime(2026, 1, 5)), '2026-01-05'); // 月、日都补零
    });

    test('忽略时分秒(同一天 key 相同)', () {
      expect(practiceDayKey(DateTime(2026, 8, 6, 0, 0)), '2026-08-06');
      expect(practiceDayKey(DateTime(2026, 8, 6, 23, 59, 59)), '2026-08-06');
    });
  });

  group('currentStreak 连续打卡', () {
    // 固定"今天"= 2026-08-06;d(n) = n 天前的日期键,用相对算免得手写一堆日期。
    final today = DateTime(2026, 8, 6);
    String d(int daysAgo) => practiceDayKey(today.subtract(Duration(days: daysAgo)));

    test('空列表 → 0', () {
      expect(currentStreak([], today), 0);
    });

    test('只练了今天 → 1', () {
      expect(currentStreak([d(0)], today), 1);
    });

    test('今天 + 往前连续 → 全数上', () {
      expect(currentStreak([d(0), d(1), d(2)], today), 3);
    });

    test('乱序不影响(按集合查,不看列表顺序)', () {
      expect(currentStreak([d(2), d(0), d(1)], today), 3);
    });

    test('今天还没练、但昨天起连练 → 从昨天数(streak 仍算到昨天为止)', () {
      // 今天没练,昨天 + 前天练了 → 2(今天再练就续上 3)
      expect(currentStreak([d(1), d(2)], today), 2);
    });

    test('今天昨天都没练 → 0(即使更早连练过,早就断了)', () {
      expect(currentStreak([d(2), d(3), d(4)], today), 0);
    });

    test('中间断了一天:只数到断点', () {
      // 今天、昨天练了,前天(2 天前)断了,大前天又练 → 只数 2(连练在昨天断)
      expect(currentStreak([d(0), d(1), d(3)], today), 2);
    });
  });
}
