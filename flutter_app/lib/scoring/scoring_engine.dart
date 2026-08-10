// 跟弹打分引擎(第61步):起音检测 + 计时准度评分 + 练习会话评分跟踪。
//
// 纯 Dart(不依赖 Flutter):只跟数字打交道,UI 显示不在这。可无头测试全部计分逻辑。
//
// 管线: MicCapture samples → OnsetDetector(能量阈值起音) → TimingScorer(onset vs expected time)
// → SessionScore(累计 good/early/late/missed → 准确率 → 等级)。
import 'dart:math';
import 'dart:typed_data';

/// 单拍的计时判定。
enum BeatJudgment { good, early, late, missed }

/// 能量起音检测器:从麦克风流判定用户何时弹了一下。
/// 算法:1024 样本(≈23ms)滑窗 RMS,连续低于阈值视为静音;RMS 超过阈值以上时触发一次 onset。
/// 触发后需等到再次低于阈值 + minSilenceMs 才能再触发(防一响判多次)。
class OnsetDetector {
  final double threshold;      // RMS 阈值,低于它 = 静音(默认 0.02,根据实际弹奏音量 tune)
  final int windowSize;        // 滑窗大小(samples)
  final int minSilenceMs;      // 两次 onset 之间最短静音(ms)
  final int sampleRate;

  double _rms = 0;             // 当前窗口的 RMS
  bool _wasAbove = false;      // 上一帧是否在阈值以上
  int _silenceSamples = 0;     // 已在静音中累积了多少样本
  int _minSilenceSamples;      // minSilenceMs 换算成样本数

  OnsetDetector({
    this.threshold = 0.02,
    this.windowSize = 1024,
    this.minSilenceMs = 120,
    this.sampleRate = 44100,
  }) : _minSilenceSamples = (minSilenceMs * sampleRate / 1000).round();

  /// 喂一帧 Float64 样本。返回 true = 这一帧检测到一次起音。
  bool feed(Float64List samples) {
    if (samples.isEmpty) return false;

    // 算本帧 RMS
    var sum = 0.0;
    for (final v in samples) {
      sum += v * v;
    }
    final frameRms = sqrt(sum / samples.length);
    // 简单 EMA 平滑(系数 0.3):避免一帧抖动误触发
    _rms = _rms * 0.7 + frameRms * 0.3;

    final above = _rms > threshold;
    var onset = false;

    if (above && !_wasAbove && _silenceSamples >= _minSilenceSamples) {
      onset = true; // 刚刚突破阈值 + 静音够长 → 判定为新一次弹奏
    }

    if (above) {
      _silenceSamples = 0;
    } else {
      _silenceSamples += samples.length;
    }
    _wasAbove = above;
    return onset;
  }

  void reset() {
    _rms = 0;
    _wasAbove = false;
    _silenceSamples = _minSilenceSamples; // 初始认为"已静音够久",第一声就能触发
  }
}

/// 计时准度评分:拿用户实际弹的时机 vs 期望节拍,判 good/early/late/missed。
/// 容差(可调):good ≤ 80ms、early/late ≤ 250ms、超过 = missed。
class TimingScorer {
  /// 容差(毫秒):绝对值 ≤ 这个算 good。默认 80ms——练习者允许 1/12 拍左右的偏差。
  static const int goodMs = 80;
  /// 最大偏差(毫秒):超过这个就判 missed。默认 250ms——大概 1/4 拍。
  static const int maxMs = 250;

  /// 判一拍的计时。expected = 节拍器"该响"的时刻, actual = 起音检测到的时刻(可空 = 没检测到)。
  /// 返回判定 + 偏差毫秒(正=晚,负=早)。
  static ({BeatJudgment judgment, double deviationMs}) judge(
    DateTime expected,
    DateTime? actual,
  ) {
    if (actual == null) return (judgment: BeatJudgment.missed, deviationMs: double.nan);
    final dev = actual.difference(expected).inMilliseconds.toDouble();
    final absMs = dev.abs();
    if (absMs <= goodMs) return (judgment: BeatJudgment.good, deviationMs: dev);
    if (absMs <= maxMs) {
      return (judgment: dev < 0 ? BeatJudgment.early : BeatJudgment.late, deviationMs: dev);
    }
    return (judgment: BeatJudgment.missed, deviationMs: dev);
  }
}

/// 一次练习的累计评分:记录每拍的结果 + 汇总准确率 + 等级。
class SessionScore {
  int good = 0;
  int early = 0;
  int late = 0;
  int missed = 0;
  int extra = 0; // 用户多弹了(没期望的拍点但有 onset)

  int get total => good + early + late + missed;
  /// 计时准确率(0~1):good / total。没弹过任何拍返回 0。
  double get accuracy => total > 0 ? good / total : 0;

  /// 等级(S/A/B/C/D):
  /// S ≥ 0.95, A ≥ 0.85, B ≥ 0.70, C ≥ 0.50, D < 0.50。
  String get grade {
    if (total == 0) return '—';
    if (accuracy >= 0.95) return 'S';
    if (accuracy >= 0.85) return 'A';
    if (accuracy >= 0.70) return 'B';
    if (accuracy >= 0.50) return 'C';
    return 'D';
  }

  /// 记录一拍的判定。
  void record(BeatJudgment j) {
    switch (j) {
      case BeatJudgment.good: good++; break;
      case BeatJudgment.early: early++; break;
      case BeatJudgment.late: late++; break;
      case BeatJudgment.missed: missed++; break;
    }
  }

  /// 平均偏差(ms):只算有检测到的拍(good/early/late 的绝对值平均)。null = 没任何有效拍。
  double? get avgDeviationMs {
    var sum = 0.0;
    var n = 0;
    // avgDeviation 没法从 record 简单算——调用方自行维护偏差列表。
    // 这里只返回 null,不在 SessionScore 里存每拍偏差(太重);由调用方算。
    return null;
  }

  void reset() {
    good = 0; early = 0; late = 0; missed = 0; extra = 0;
  }
}
