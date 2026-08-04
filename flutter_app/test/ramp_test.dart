// 自动提速纯函数 nextRampTempo 的无头单元测试。
// 不连手机(flutter test):锁它的边界行为——每遍 +3 / 截到原速不冒头 / 到顶不再涨 / step 可调。
// 把提速逻辑从引擎里抽成纯函数(不依赖 Timer / setState),就是为了这里能直接、稳定地测。
import 'package:flutter_test/flutter_test.dart';

import 'package:ukulele_demo/models.dart';

void main() {
  group('nextRampTempo 自动提速', () {
    test('未到原速:每过一遍 +3', () {
      expect(nextRampTempo(60, 100), 63);
      expect(nextRampTempo(63, 100), 66);
    });

    test('加这一下会超过原速:截到原速,不冒头', () {
      // 99 + 3 = 102 > 100,截到 100
      expect(nextRampTempo(99, 100), 100);
    });

    test('已到原速:不再涨(停在 cap)', () {
      expect(nextRampTempo(100, 100), 100);
    });

    test('超过原速(手动加过速):也不往上加', () {
      expect(nextRampTempo(120, 100), 120);
    });

    test('step 可调(默认 3,可传别的)', () {
      expect(nextRampTempo(60, 100, step: 5), 65);
      expect(nextRampTempo(98, 100, step: 5), 100); // 截顶,不冒头
    });
  });
}
