// 基频检测(给真调音器用):给一段单声道 PCM 样本 + 采样率,返回基频(Hz);测不到返回 null。
//
// 纯 Dart(只依赖 dart:typed_data + dart:math),不碰 Flutter / 麦克风 / SoLoud —— 这样能用
// flutter test 在电脑上无头验证"给个已知频率的正弦波,能不能测回原频率"(跟 strum_synth 同一套测试套路)。
// "测得稳不稳、真琴吵不吵"得装机拿真琴试,但"算法对不对"这里就能锁死。
//
// 用的是 YIN(de Cheveigné & Kawahara 2002)——单声部基频检测的经典算法,比朴素自相关更不容易
// 认错八度(把 G 听成低八度的 G)。步骤:
//   1) 差分函数  d(τ) = Σ (x[j] - x[j+τ])²
//   2) 累积均值归一化  d'(τ) = d(τ)·τ / Σ_{j=1..τ} d(j),d'(0)=1
//   3) 绝对阈值:找第一个 d' < threshold 且是局部最小的 τ;都没有就取范围内的全局最小(还太大就放弃)
//   4) 抛物线插值:在选中 τ 附近用抛物线把 τ 精确到亚采样(音高更准)
//   5) f0 = sampleRate / τ
import 'dart:math';
import 'dart:typed_data';

class PitchDetector {
  /// d'(τ) 绝对阈值:低于它才算"找到周期了"。0.10~0.15 常用;越大越容易认、但越容易误判。
  final double threshold;

  /// 只在这个频率范围里找基频。既加速(τ 上下界卡死)、又防止测到范围外的乱真峰(嗡嗡底噪、
  /// 八度误判)。默认偏宽(70~1000Hz)通用;调音页用尤克里里范围(约 150~500Hz)实例化。
  final double minFrequency;
  final double maxFrequency;

  const PitchDetector({
    this.threshold = 0.15,
    this.minFrequency = 70,
    this.maxFrequency = 1000,
  });

  /// 给一段样本 [samples](单声道,-1..1)+ [sampleRate],返回基频(Hz);测不到(太安静 /
  /// 太短 / 没周期)返回 null。
  double? detect(Float64List samples, int sampleRate) {
    final n = samples.length;
    if (n < 16) return null;

    // 安静门:均方太小说明没在弹(只剩环境噪声),直接返回 null,免得把噪声当成音高。
    // 第56步:1e-4→5e-4(约 -66 dBFS),减少环境噪声误判。
    var sumSq = 0.0;
    for (final v in samples) {
      sumSq += v * v;
    }
    if (sumSq / n < 5e-4) return null;

    // τ(延后采样数)上下界:由目标频率范围反推。τ = sampleRate / freq。
    final minTau = max(2, (sampleRate / maxFrequency).floor());
    final maxTau = min(n - 1, (sampleRate / minFrequency).ceil());
    if (maxTau <= minTau) return null; // 缓冲太短、覆盖不到最低频率

    // 1)+2) 差分 + 累积均值归一化(一遍算完)。
    final yin = Float64List(maxTau + 1);
    yin[0] = 1.0;
    var running = 0.0; // Σ_{j=1..τ} d(j)
    for (var tau = 1; tau <= maxTau; tau++) {
      var sum = 0.0;
      for (var j = 0; j + tau < n; j++) {
        final d = samples[j] - samples[j + tau];
        sum += d * d;
      }
      running += sum;
      yin[tau] = running > 0 ? sum * tau / running : 0.0; // running==0(完全周期)→ 0 = 完美匹配
    }

    // 3) 绝对阈值:第一个 < threshold 的局部最小(找到后顺势往后走到谷底)。
    var tauEstimate = -1;
    for (var tau = minTau; tau < maxTau; tau++) {
      if (yin[tau] < threshold) {
        while (tau + 1 < maxTau && yin[tau + 1] < yin[tau]) {
          tau++;
        }
        tauEstimate = tau;
        break;
      }
    }
    if (tauEstimate < 0) {
      // 阈值下没有:取范围内的全局最小做兜底;连全局最小都太大(>0.8)说明信号没清晰周期 → 放弃。
      var bestVal = 1.0;
      var bestTau = -1;
      for (var tau = minTau; tau <= maxTau; tau++) {
        if (yin[tau] < bestVal) {
          bestVal = yin[tau];
          bestTau = tau;
        }
      }
      if (bestTau < 0 || bestVal > 0.8) return null;
      tauEstimate = bestTau;
    }

    // 4) 抛物线插值:用 τ-1/τ/τ+1 三点拟合抛物线,把谷底精确到亚采样(音高误差从 ~1Hz 降到 <0.1Hz)。
    var better = tauEstimate.toDouble();
    if (tauEstimate > 0 && tauEstimate < maxTau) {
      final a = yin[tauEstimate - 1], b = yin[tauEstimate], c = yin[tauEstimate + 1];
      final denom = a + c - 2 * b;
      if (denom.abs() > 1e-9) {
        final shift = 0.5 * (a - c) / denom;
        if (shift.abs() < 1.0) better = tauEstimate + shift; // 限制偏移在 ±1 内防跑飞
      }
    }

    // 5) f0 = sampleRate / τ。再卡一次频率范围(兜底)。
    final freq = sampleRate / better;
    if (freq < minFrequency || freq > maxFrequency) return null;
    return freq;
  }
}

// —— 频率 → 音名(给"自动识别到的音"显示用)——
// 纯函数、无副作用:抽出来是为了能在无头测试里锁边界(440=A4、261.63=C4、偏高半音 cents 为正)。

/// 一个频率对应的音名 + 八度 + 偏离最近音分的"音分(cents)"。
/// cents < 0 偏低、> 0 偏高、范围 ±50 以内(超过 50 会算到相邻的音名上)。
class NoteResult {
  final String name; // 'C' / 'C#' / ... / 'A' / 'A#' / 'B'
  final int octave; // 科学音高记号:A4 = 440Hz 那个 4
  final double cents; // 相对最近音名的音分偏差(约 ±50)
  const NoteResult({required this.name, required this.octave, required this.cents});
}

const _noteNames = [
  'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B',
];

/// 频率 → 最近音名 + 八度 + 音分偏差。[a4] = A4 的基准频率(默认 440Hz,标准音高);
/// 调音页可传 442 等做【校准】(交响音高)→ "准"的参照点整体平移,cents 跟着重算
/// (同一频率在 a4 不同时读出的音分不同:440Hz 在 a4=442 时读成约 -8 音分偏低)。
/// 音名 / 八度基本不变(只在恰好卡在两音正中间的边界上才可能跳),变的主要是 cents。
NoteResult frequencyToNote(double freq, {double a4 = 440}) {
  // 距 A4 的半音数 = 12·log2(freq/a4)。
  final semis = 12 * log(freq / a4) / log(2);
  final midi = (69 + semis).round(); // 最近 MIDI 音高(整数)
  final cents = (semis - (midi - 69)) * 100; // 小数部分 × 100 = 音分
  final nameOctave = ((midi % 12) + 12) % 12; // 安全取模(MIDI 理论上 ≥0,兜底防负)
  return NoteResult(
    name: _noteNames[nameOctave],
    octave: midi ~/ 12 - 1, // MIDI 60 = C4: 60~/12=5, -1=4 ✓;MIDI 69=A4 ✓
    cents: cents,
  );
}

/// 两个频率相差多少音分(可正可负):1200 音分 = 一个八度(频率 2 倍)。
/// 给调音器的【弦距过滤】用——选了目标弦后,检测音离目标超过阈值(如 600 音分)就当没听到,
/// 挡 YIN 偶发的八度误报(如 A4=440 被听成低八度 A3=220,差 1200 音分)。纯函数、无头可测。
double centsBetween(double f1, double f2) => 1200 * log(f1 / f2) / log(2);
