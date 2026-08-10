// formatPracticeSec 纯函数的无头单元测试(不连手机)。
// 锁它的三段边界:<60s 显示秒、够 1 分显示分、够 1 小时显示「时分」。
// 跟 nextRampTempo 一样从界面里抽成纯函数放 models.dart,就是为了这里能直接、稳定地测。
import 'package:flutter_test/flutter_test.dart';

import 'package:ukulele_demo/models.dart';

void main() {
  group('formatPracticeSec 秒数格式化', () {
    test('<60 秒:显示秒', () {
      expect(formatPracticeSec(0), '0s');
      expect(formatPracticeSec(1), '1s');
      expect(formatPracticeSec(59), '59s');
    });

    test('够 1 分、不到 1 小时:显示分', () {
      expect(formatPracticeSec(60), '1m');
      expect(formatPracticeSec(90), '1m'); // 90s = 1m10s,只取整分
      expect(formatPracticeSec(3599), '59m');
    });

    test('够 1 小时:显示「时分」', () {
      expect(formatPracticeSec(3600), '1h0m');
      expect(formatPracticeSec(3660), '1h1m'); // 61 分 = 1h1m
      expect(formatPracticeSec(4320), '1h12m');
      expect(formatPracticeSec(7325), '2h2m'); // 7325s = 122m5s = 2h2m
    });
  });

  group('formatTranspose 移调格式化', () {
    test('0:空串(不移调就不显示)', () {
      expect(formatTranspose(0), '');
    });

    test('正偏移:带 + 号、末尾带分隔符(拼信息行用)', () {
      expect(formatTranspose(2), '移调 +2半音 · ');
      expect(formatTranspose(6), '移调 +6半音 · ');
    });

    test('负偏移:带 - 号', () {
      expect(formatTranspose(-3), '移调 -3半音 · ');
      expect(formatTranspose(-6), '移调 -6半音 · ');
    });
  });
}
