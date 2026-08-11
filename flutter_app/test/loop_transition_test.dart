// 循环过渡拍:isLastIndex 纯函数的无头单元测试(跟 ramp_test 一个套路)。
//
// 过渡拍"只在整轮走完才插、不是每个元素都插"这条规则,核心就是 isLastIndex 这个判断。
// 把它从琶音/指弹屏抽成纯函数,就是为了这里能直接、稳定地锁它的边界,不依赖 Timer / setState。
// 真正"回跳后嗒满1小节再开下一遍"的时序行为是 Timer 驱动的,装机听(跟预备拍一个层),
// 这里只锁判断本身——跟既有 ramp_test 锁 nextRampTempo、不锁 Timer 驱动的提速时序同理。
import 'package:flutter_test/flutter_test.dart';

import 'package:ukulele_demo/models.dart';

void main() {
  group('isLastIndex 循环过渡触发判断', () {
    test('末位 → true(再走一步就绕回开头,该插过渡拍)', () {
      expect(isLastIndex(3, 4), isTrue); // 4 个和弦,下标3 = 最后一个
      expect(isLastIndex(1, 2), isTrue); // 2 个,下标1 = 最后一个
    });

    test('非末位 → false(还没到整轮末尾,不插)', () {
      expect(isLastIndex(0, 4), isFalse);
      expect(isLastIndex(2, 4), isFalse);
    });

    test('单元素序列 → false(就1个、不绕环,不插过渡)', () {
      expect(isLastIndex(0, 1), isFalse);
    });

    test('空序列 → false', () {
      expect(isLastIndex(0, 0), isFalse);
    });

    test('越界下标 → false(防御)', () {
      expect(isLastIndex(-1, 4), isFalse);
      expect(isLastIndex(4, 4), isFalse);
    });
  });
}
