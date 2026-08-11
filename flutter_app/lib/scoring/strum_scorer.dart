// 扫弦评分(给「跟弹评分」用):给定【期望扫弦的时刻】(节拍器推出来的)和【麦检出的 onset 时刻】,
// 算出用户这一遍弹得怎么样——命中 / 漏拍 / 早 / 晚 / 准,以及准确率 %。
//
// 纯函数、无副作用、不碰 Flutter / 音频:跟 OnsetDetector / PitchDetector 一个套路,能用 flutter test
// 在电脑上无头验证"给两组时刻,匹配 / 统计对不对"。"检得稳不稳"是 OnsetDetector 和装机的事,这里只管
// 拿到两组时刻后算得对不对。
//
// 匹配用「全局最近者优先」的贪心:把所有(期望,onset)候选对按距离升序排,从最近的开始配,配过的就不再配。
// 这样在快歌容差窗重叠时(如 200BPM 半拍 = 150ms < 容差 180ms,两拍窗口会叠)也不会把 onset 配错拍——
// 比"逐拍找最近"的朴素贪心靠谱(后者会把夹在两拍中间的 onset 抢给前一拍、后一拍判漏)。

/// 一拍扫弦的判定结果(给 live 圆点 / 总结用)。
enum StrumJudgment { missed, early, onTime, late }

/// 单下扫弦的判定 + 误差。[errorSec] = onset − expected:正 = 偏晚、负 = 偏早;missed 时无意义。
class StrumVerdict {
  final StrumJudgment judgment;
  final double errorSec;
  const StrumVerdict(this.judgment, this.errorSec);
}

/// 一次评分会话的汇总。verdicts 按期望时刻【升序】(= 演奏时间顺序)排列,给界面画"最近 N 下"圆点。
class ScoreResult {
  final int total; // 期望扫弦数(dir != rest 的拍)
  final int hits; // 在容差内匹配到的
  final int missed; // 没匹配到 onset 的
  final int early; // hits 里偏早的(|error| > onTimeWindow 且 error < 0)
  final int onTime; // hits 里准的(|error| ≤ onTimeWindow)
  final int late; // hits 里偏晚的(error > 0)
  final double accuracy; // hits / total(0..1);total=0 → 0
  final double meanAbsErrorSec; // hits 的 |error| 均值
  final double meanSignedErrorSec; // hits 的 error 均值(正=整体偏晚、负=整体偏早 —— 校准延迟的指南针)
  final List<StrumVerdict> verdicts; // 每个期望一个,升序

  const ScoreResult({
    required this.total,
    required this.hits,
    required this.missed,
    required this.early,
    required this.onTime,
    required this.late,
    required this.accuracy,
    required this.meanAbsErrorSec,
    required this.meanSignedErrorSec,
    required this.verdicts,
  });
}

/// 一个候选匹配对(onset 下标, expected 下标, 距离)。私有,仅供 [score] 内部排序用。
class _Pair {
  final int oi;
  final int ei;
  final double dist;
  const _Pair(this.oi, this.ei, this.dist);
}

/// 评分主函数。
///
/// - [expectedTimes]:每个【应当扫弦】的拍的时刻(秒,调用方统一时钟)。不必预排序(内部排)。
/// - [onsetTimes]:OnsetDetector 检出的扫弦时刻(秒,同一时钟;【未】减延迟)。
/// - [tolerance]:容差(秒)。|onset − expected| 超过它就算漏(默认 180ms)。
/// - [latencyOffset]:系统延迟(秒,麦输入 + 扬声器输出)。onset 实际发生 = 检出时刻 − latencyOffset;
///   不减的话每一下都会显得偏晚一个延迟量 → 准确率假性偏低。默认 0(桌面测试用),装机给 ~0.1。
/// - [onTimeWindow]:「准」的窗口(秒,默认 50ms)。命中后 |error| ≤ 它算准,否则分早 / 晚。
ScoreResult score({
  required List<double> expectedTimes,
  required List<double> onsetTimes,
  double tolerance = 0.18,
  double latencyOffset = 0,
  double onTimeWindow = 0.05,
}) {
  // onset 减延迟 = 用户实际弹的时刻。
  final onsets = latencyOffset == 0
      ? List<double>.of(onsetTimes)
      : List<double>.generate(onsetTimes.length, (i) => onsetTimes[i] - latencyOffset);
  onsets.sort();
  final expected = List<double>.of(expectedTimes)..sort();

  // 收集所有候选对(只收距离 ≤ tolerance 的),按距离升序排。
  final pairs = <_Pair>[];
  for (var oi = 0; oi < onsets.length; oi++) {
    final o = onsets[oi];
    var ei = _lowerBound(expected, o - tolerance);
    while (ei < expected.length && expected[ei] <= o + tolerance) {
      pairs.add(_Pair(oi, ei, (expected[ei] - o).abs()));
      ei++;
    }
  }
  pairs.sort((a, b) => a.dist.compareTo(b.dist));

  // 全局最近者优先:从最近的候选对开始配,配过的 onset / 期望都不再配。
  final onsetMatched = List<bool>.filled(onsets.length, false);
  final expMatched = List<bool>.filled(expected.length, false);
  final expError = List<double>.filled(expected.length, 0.0);
  for (final p in pairs) {
    if (onsetMatched[p.oi] || expMatched[p.ei]) continue;
    onsetMatched[p.oi] = true;
    expMatched[p.ei] = true;
    expError[p.ei] = onsets[p.oi] - expected[p.ei]; // 正=晚、负=早
  }

  // 统计 + 逐期望 verdict(按升序 = 时间顺序)。
  var hits = 0, missed = 0, early = 0, onTime = 0, late = 0;
  var sumAbs = 0.0, sumSigned = 0.0;
  final verdicts = <StrumVerdict>[];
  for (var i = 0; i < expected.length; i++) {
    if (!expMatched[i]) {
      missed++;
      verdicts.add(const StrumVerdict(StrumJudgment.missed, 0.0));
      continue;
    }
    hits++;
    final err = expError[i];
    sumAbs += err.abs();
    sumSigned += err;
    final StrumJudgment j;
    if (err.abs() <= onTimeWindow) {
      j = StrumJudgment.onTime;
      onTime++;
    } else if (err < 0) {
      j = StrumJudgment.early;
      early++;
    } else {
      j = StrumJudgment.late;
      late++;
    }
    verdicts.add(StrumVerdict(j, err));
  }

  final total = expected.length;
  return ScoreResult(
    total: total,
    hits: hits,
    missed: missed,
    early: early,
    onTime: onTime,
    late: late,
    accuracy: total == 0 ? 0.0 : hits / total,
    meanAbsErrorSec: hits == 0 ? 0.0 : sumAbs / hits,
    meanSignedErrorSec: hits == 0 ? 0.0 : sumSigned / hits,
    verdicts: verdicts,
  );
}

/// 二分下界:第一个 a[i] >= v 的下标(给上面定位容差窗左端用)。比线性扫快,且 expected 不大也稳。
int _lowerBound(List<double> a, double v) {
  var lo = 0, hi = a.length;
  while (lo < hi) {
    final mid = lo + (hi - lo) ~/ 2;
    if (a[mid] < v) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}
