// 跟弹评分匹配(score / ScoreResult / StrumVerdict)的无头单元测试。
// 不连手机(flutter test):给「期望扫弦时刻」和「onset 时刻」两组数,看命中 / 漏 / 早 / 晚 / 准 / 准确率
// 算得对不对、容差边界对不对、延迟平移对不对。算法"认得准不准"是 OnsetDetector + 装机的事,这里只管
// "拿到两组时刻后算得对不对"——锁死匹配逻辑(尤其快歌容差窗重叠时别配错拍)。
import 'package:flutter_test/flutter_test.dart';
import 'package:ukulele_demo/scoring/strum_scorer.dart';

void main() {
  group('完美匹配', () {
    test('期望和 onset 完全对齐 → 全准、准确率 100%', () {
      final r = score(expectedTimes: [1.0, 2.0, 3.0], onsetTimes: [1.0, 2.0, 3.0]);
      expect(r.total, 3);
      expect(r.hits, 3);
      expect(r.missed, 0);
      expect(r.onTime, 3);
      expect(r.early, 0);
      expect(r.late, 0);
      expect(r.accuracy, closeTo(1.0, 1e-9));
      expect(r.meanAbsErrorSec, closeTo(0, 1e-9));
    });
  });

  group('漏拍', () {
    test('一个 onset 都没有 → 全漏、准确率 0', () {
      final r = score(expectedTimes: [1.0, 2.0, 3.0], onsetTimes: []);
      expect(r.hits, 0);
      expect(r.missed, 3);
      expect(r.accuracy, 0);
    });
  });

  group('早 / 晚 / 准 分类(onTimeWindow=50ms)', () {
    test('|error|≤50ms → 准', () {
      final r = score(expectedTimes: [1.0], onsetTimes: [1.02], latencyOffset: 0);
      expect(r.hits, 1);
      expect(r.onTime, 1);
      expect(r.verdicts.first.judgment, StrumJudgment.onTime);
    });
    test('error<0 且 |error|>50ms → 早', () {
      // 期望 1.0,onset 0.9 → error -0.1(早 100ms)
      final r = score(expectedTimes: [1.0], onsetTimes: [0.9]);
      expect(r.early, 1);
      expect(r.verdicts.first.judgment, StrumJudgment.early);
      expect(r.verdicts.first.errorSec, closeTo(-0.1, 1e-9));
    });
    test('error>0 且 |error|>50ms → 晚', () {
      final r = score(expectedTimes: [1.0], onsetTimes: [1.1]);
      expect(r.late, 1);
      expect(r.verdicts.first.judgment, StrumJudgment.late);
      expect(r.verdicts.first.errorSec, closeTo(0.1, 1e-9));
    });
  });

  group('容差边界(tolerance=180ms)', () {
    test('正好 180ms → 仍算命中(≤)', () {
      final r = score(expectedTimes: [1.0], onsetTimes: [1.18]);
      expect(r.hits, 1);
    });
    test('181ms → 算漏(>tolerance)', () {
      final r = score(expectedTimes: [1.0], onsetTimes: [1.19]);
      expect(r.missed, 1);
      expect(r.hits, 0);
    });
  });

  group('延迟平移 latencyOffset', () {
    test('onset 整体晚 100ms、latencyOffset=0.1 → 抵消成准', () {
      // 不减延迟:误差 +0.1 → 晚;减 0.1 后:onset=1.0 → 准
      final r = score(expectedTimes: [1.0], onsetTimes: [1.1], latencyOffset: 0.10);
      expect(r.hits, 1);
      expect(r.onTime, 1);
      expect(r.meanSignedErrorSec, closeTo(0, 1e-9));
    });
    test('不减延迟 → 同一 onset 显得偏晚(对照)', () {
      final r = score(expectedTimes: [1.0], onsetTimes: [1.1], latencyOffset: 0);
      expect(r.late, 1);
    });
  });

  group('快歌容差窗重叠 —— 全局最近者优先(关键)', () {
    test('两拍间隔 150ms(< tolerance 180ms)、onset 落在第二拍 → 配给第二拍、第一拍漏', () {
      // 朴素"逐拍找最近"会把 0.16 抢给第一拍(0),第二拍(0.15)判漏;全局最近优先能配对。
      final r = score(expectedTimes: [0.0, 0.15], onsetTimes: [0.16]);
      expect(r.hits, 1);
      expect(r.missed, 1);
      // verdicts 按期望升序:[0.0, 0.15]
      expect(r.verdicts[0].judgment, StrumJudgment.missed);
      expect(r.verdicts[1].judgment, StrumJudgment.onTime); // 0.16-0.15=0.01 ≤ 50ms
      expect(r.verdicts[1].errorSec, closeTo(0.01, 1e-9));
    });
    test('两个 onset 两个期望、交叉时按总误差最小配', () {
      // 期望 [0, 0.15],onset [0.10, 0.16]。最优:0.10→0(0.10)、0.16→0.15(0.01)。
      final r = score(expectedTimes: [0.0, 0.15], onsetTimes: [0.10, 0.16]);
      expect(r.hits, 2);
      expect(r.verdicts[0].judgment, StrumJudgment.late); // 0.10-0.0=+0.10 → 晚
      expect(r.verdicts[1].judgment, StrumJudgment.onTime); // 0.16-0.15=0.01 → 准
    });
  });

  group('多出来的 onset(v1 不罚 extras)', () {
    test('onset 比期望多 → 多的不计、不漏、准确率仍 100%', () {
      final r = score(expectedTimes: [1.0], onsetTimes: [1.0, 1.5]);
      expect(r.hits, 1);
      expect(r.missed, 0);
      expect(r.accuracy, closeTo(1.0, 1e-9));
    });
  });

  group('空 / 边界', () {
    test('两个都空 → total=0、accuracy=0、verdicts 空', () {
      final r = score(expectedTimes: [], onsetTimes: []);
      expect(r.total, 0);
      expect(r.accuracy, 0);
      expect(r.verdicts, isEmpty);
    });
    test('只有 onset 没期望 → total=0(全当 extras 忽略)', () {
      final r = score(expectedTimes: [], onsetTimes: [1.0, 2.0]);
      expect(r.total, 0);
      expect(r.hits, 0);
    });
  });

  group('整体倾向 meanSignedError(校准延迟的指南针)', () {
    test('两下都早 100ms → meanSigned ≈ -0.10、都判早(提示:延迟调小 / 你抢拍)', () {
      final r = score(expectedTimes: [1.0, 2.0], onsetTimes: [0.90, 1.90]);
      expect(r.early, 2);
      expect(r.meanSignedErrorSec, closeTo(-0.10, 1e-9)); // 负 = 整体偏早
    });
    test('两下都晚 100ms → meanSigned ≈ +0.10(提示:延迟调大 / 你拖拍)', () {
      final r = score(expectedTimes: [1.0, 2.0], onsetTimes: [1.10, 2.10]);
      expect(r.late, 2);
      expect(r.meanSignedErrorSec, closeTo(0.10, 1e-9)); // 正 = 整体偏晚
    });
  });
}
