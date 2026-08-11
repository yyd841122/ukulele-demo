// 扫弦起始检测(给「跟弹评分」用):给麦克风的一段样本,告诉我里面哪儿发生了扫弦(onset),
// 返回这些 onset 的时刻(秒)。纯 Dart(只依赖 dart:typed_data + dart:math),不碰 Flutter / SoLoud
// / 麦克风 —— 这样能用 flutter test 在电脑上无头验证"给个合成的扫弦声,能不能检对位置"。
// "真琴吵不吵、检得稳不稳"得装机拿真琴试,但"算法对不对"这里就能锁死(跟 PitchDetector 同套路)。
//
// =为什么需要滤波链=
// 评分时 app 自己在打节拍器嗒声(嘀声 beep = 880Hz 纯音、重音 1320Hz)。麦会把嗒声也收进去,
// 不滤掉的话每拍都会被当成"用户扫了一下"→ 分数虚高、失去意义。所以先把嗒声从信号里剔掉再检 onset:
//   高通 150Hz(去环境隆隆 / 跟唱人声 / 碰琴底噪)→ 陷波 880Hz → 陷波 1320Hz(去嘀声基频 + 重音)
// 扫弦是宽带瞬态(能量遍布几百~几千 Hz),只在 880/1320 各挖一个窄缝几乎不影响它;嗒声是窄带纯音,
// 正好被陷波器深深吃掉。再配合 strum_synth 里给评分嗒声加的 4ms 淡入(软化硬起攻击的宽带溅射),
// 嗒声能被压到 >40dB(几乎不进麦),扫弦则照样被抓到。
//
// = onset 算法 =
// 把滤波后的信号按 ~10ms 一帧算功率(均方)→ 算相邻帧功率的正向差(flux,半波整流)→
// flux 超过自适应阈值(k × 最近 ~0.5s 的 flux 均值,且过一个绝对地板)且功率高于安静门、
// 且距上一个 onset 超过 refractory(120ms,免得一下扫弦检成两下)→ 记一个 onset。
// 这是能量通量法(energy flux)——对扫弦这种敲击式瞬态最拿手(比频谱 flux 简单、够用)。
import 'dart:math';
import 'dart:typed_data';

/// 二阶 IIR 滤波器(双二阶 / biquad),转置直接 II 型(数值稳、只要 2 个状态 z1/z2)。
/// 系数按 Audio EQ Cookbook(Robert Bristow-Johnson)算,归一化到 a0=1。
/// 跨 chunk 有状态:实例一直持有 z1/z2,连续喂数据 = 连续滤波(不会重滤、不会断)。
/// 设成公开(非私有):无头测试要直接拼一条滤波链,断言它对 880/1320Hz 衰减 ≥40dB(核心鲁棒性)。
class Biquad {
  final double b0, b1, b2, a1, a2;
  double _z1 = 0, _z2 = 0;

  Biquad._(this.b0, this.b1, this.b2, this.a1, this.a2);

  /// 高通(Butterworth,Q≈0.707 平坦)。用来去低频隆隆 / 人声 / 碰琴。
  factory Biquad.highpass(double freq, int sampleRate, [double q = 0.707]) {
    final w = 2 * pi * freq / sampleRate;
    final cw = cos(w), sw = sin(w);
    final alpha = sw / (2 * q);
    final b0 = (1 + cw) / 2, b1 = -(1 + cw), b2 = (1 + cw) / 2;
    final a0 = 1 + alpha, a1 = -2 * cw, a2 = 1 - alpha;
    return Biquad._(b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0);
  }

  /// 陷波(notch):在 freq 处深深挖一缝、两边很快恢复。Q 越大缝越窄越深。用来精准剔嗒声纯音。
  factory Biquad.notch(double freq, int sampleRate, [double q = 7]) {
    final w = 2 * pi * freq / sampleRate;
    final cw = cos(w), sw = sin(w);
    final alpha = sw / (2 * q);
    final b0 = 1.0, b1 = -2 * cw, b2 = 1.0;
    final a0 = 1 + alpha, a1 = -2 * cw, a2 = 1 - alpha;
    return Biquad._(b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0);
  }

  /// 原地滤波(边读边写回 [s]):每个样本 x → y=b0·x+z1,顺手更新 z1/z2。
  /// 局部变量缓存系数 + 状态,减少 this 读写(热路径)。
  void processInPlace(Float64List s) {
    var z1 = _z1, z2 = _z2;
    final b0 = this.b0, b1 = this.b1, b2 = this.b2, a1 = this.a1, a2 = this.a2;
    for (var i = 0; i < s.length; i++) {
      final x = s[i];
      final y = b0 * x + z1;
      z1 = b1 * x - a1 * y + z2;
      z2 = b2 * x - a2 * y;
      s[i] = y;
    }
    _z1 = z1;
    _z2 = z2;
  }

  /// 复位状态(新一次评分会话前调:别让上次的滤波器尾 / 状态串进来)。
  void reset() {
    _z1 = 0;
    _z2 = 0;
  }
}

/// 扫弦起始检测器。流式:调用方每来一段麦样本 [process] 一次,带上这段【末样本的到达时刻】
/// (秒,跟调用方统一的 Stopwatch 时钟),返回这段里新检出的 onset 时刻(同一时钟)。
/// 内部跨 chunk 维持滤波器状态 + 过滤后的尾部样本(拼帧用)+ flux 滑窗 + refractory 计时。
class OnsetDetector {
  final int sampleRate;
  final int hop; // 一帧多少样本(默认 ~10ms)
  final double refractorySec; // 两个 onset 之间至少隔多久(免一下扫弦检两下)
  final double adaptiveK; // 阈值 = k × 近期 flux 均值
  final double fluxFloor; // flux 绝对地板:低于它一律不算(挡环境细碎抖动)
  final double minEnergy; // 功率安静门:低于它说明没在弹(挡底噪)
  final int minSustainFrames; // 命中要连续多少帧还在 floor 上才算(挡短促嘀声残留——见 _detect)

  final Biquad _hp;
  final Biquad _notch1;
  final Biquad _notch2;

  // 上一次没凑满一帧的【已滤波】尾部样本,留到这次拼帧(注意:只存已滤波的,免得重复滤)。
  Float64List _carry = Float64List(0);
  double _prevEnergy = 0; // 上一帧功率(算 flux 用)

  // flux 滑窗(环缓冲)算自适应均值的"近期"基准。
  final List<double> _fluxHist;
  int _fluxIdx = 0;
  int _fluxFilled = 0;
  double _fluxSum = 0;

  double _lastOnsetSec = -1e9; // 上一个 onset 时刻(refractory 判定用);-1e9 = 还没检出过

  // —— 持续性门(sustain gate):扫弦会响 ~100ms+,陷波后剩下的短嘀声只是一下尖峰 ——
  // 上升沿先记成"候选",要它后续 minSustainFrames 帧还撑在 floor 上才确认;撑不住就弃。
  double? _candidateTime;
  int _confirmFramesLeft = 0;

  OnsetDetector({
    this.sampleRate = 44100,
    int? hop,
    this.refractorySec = 0.12,
    this.adaptiveK = 3.0,
    this.fluxFloor = 2e-4,
    this.minEnergy = 3e-4,
    this.minSustainFrames = 2,
    int historyLen = 50, // ~0.5s 的帧数(每帧 10ms),给自适应阈值滑窗用
    double hpFreq = 150,
    double notchFreq1 = 880, // 嘀声普通音基频
    double notchFreq2 = 1320, // 嘀声重音(880×1.5)
    double notchQ = 7,
  })  : hop = hop ?? (0.010 * sampleRate).round(),
        _hp = Biquad.highpass(hpFreq, sampleRate),
        _notch1 = Biquad.notch(notchFreq1, sampleRate, notchQ),
        _notch2 = Biquad.notch(notchFreq2, sampleRate, notchQ),
        _fluxHist = List<double>.filled(historyLen, 0.0);




  /// 处理一段新样本 [chunk](单声道,-1..1),[arrivalSec] = 这段末样本的时刻(秒,调用方时钟)。
  /// 返回这段里新检出的 onset 时刻列表(秒,同一时钟;不含 latencyOffset —— 那个由调用方在
  /// 匹配时减:OnsetDetector 只管信号,不管系统延迟)。
  List<double> process(Float64List chunk, double arrivalSec) {
    if (chunk.isEmpty) return const [];
    // 1) 滤波链:只滤【这次的新 chunk】(滤波器状态跨调用连续 → 不重复滤 _carry)。
    //    Float64List.fromList 拷一份,免得改到麦流里别人还在用的缓冲。
    final filt = Float64List.fromList(chunk);
    _hp.processInPlace(filt);
    _notch1.processInPlace(filt);
    _notch2.processInPlace(filt);

    // 2) 拼成连续流 = 上次滤波后的尾部(_carry)+ 这次滤波后的新样本,逐帧算功率 + 判 onset。
    final carry = _carry;
    final carryLen = carry.length;
    final total = carryLen + filt.length;
    final onsets = <double>[];
    var pos = 0;
    while (pos + hop <= total) {
      var energy = 0.0;
      for (var j = 0; j < hop; j++) {
        final gp = pos + j; // 在「carry+filt」合流里的绝对位置
        final v = gp < carryLen ? carry[gp] : filt[gp - carryLen];
        energy += v * v;
      }
      energy /= hop; // 功率(均方)
      // 帧中心在合流里的样本位置 → 换算成秒(arrivalSec 是合流末样本的时刻)。
      final centerSample = pos + hop / 2.0;
      final t = arrivalSec - (total - centerSample) / sampleRate;
      _detect(energy, t, onsets);
      pos += hop;
    }

    // 3) 尾部(< 一帧的滤波后样本)留到下次接着拼。
    final tailLen = total - pos;
    final tail = Float64List(tailLen);
    for (var j = 0; j < tailLen; j++) {
      final gp = pos + j;
      tail[j] = gp < carryLen ? carry[gp] : filt[gp - carryLen];
    }
    _carry = tail;
    return onsets;
  }

  /// 一帧的功率 → flux(正向差)→ 自适应阈值 + 地板 + 安静门 + refractory + 持续性 综合判定。
  /// 注意两处顺序坑:(1) 阈值用【加入当前 flux 之前】的滑窗均值 —— 否则当前大 flux 把自己阈值顶高、
  /// 反而检不出;(2) 滑窗无论本帧是否触发都要更新 —— 否则基准就停了。
  ///
  /// 持续性门(sustain gate):上升沿先记成候选,要后续 [minSustainFrames] 帧仍 > [minEnergy] 才确认。
  /// 用来挡陷波后剩下的【短嘀声残留】:嘀声是 30ms 纯音,陷波器把稳态压掉了,只剩起振/收尾那点尖峰
  /// (撑不过 1 帧)→ 候选被弃;扫弦是宽带瞬态 + 琴体余音,稳稳 >floor 上百毫秒 → 候选转正。
  void _detect(double energy, double t, List<double> onsets) {
    final flux = energy > _prevEnergy ? energy - _prevEnergy : 0.0; // 半波整流:只看上升
    _prevEnergy = energy;

    final meanFlux = _fluxFilled > 0 ? _fluxSum / _fluxFilled : 0.0;
    final threshold = max(adaptiveK * meanFlux, fluxFloor);

    // 更新滑窗(加入当前 flux,给后续帧当基准)。
    _fluxSum -= _fluxHist[_fluxIdx];
    _fluxHist[_fluxIdx] = flux;
    _fluxSum += flux;
    _fluxIdx = (_fluxIdx + 1) % _fluxHist.length;
    if (_fluxFilled < _fluxHist.length) _fluxFilled++;

    // 1) 候选确认中:看本帧是否还撑在 floor 上。撑不住 → 弃(是短促嘀声残留,不是扫弦)。
    if (_candidateTime != null) {
      if (energy > minEnergy) {
        _confirmFramesLeft--;
        if (_confirmFramesLeft <= 0) {
          onsets.add(_candidateTime!);
          _lastOnsetSec = _candidateTime!;
          _candidateTime = null;
        }
      } else {
        _candidateTime = null; // 没撑住 → 弃
      }
      return; // 确认窗口内不另起候选(refractory 也会挡,这里直接 return 更省事)
    }

    // 2) 否则:检测新的上升沿(过阈值 + 过 floor + 过 refractory)→ 立候选,等后续帧确认。
    if (flux > threshold &&
        energy > minEnergy &&
        (t - _lastOnsetSec) >= refractorySec) {
      _candidateTime = t;
      _confirmFramesLeft = minSustainFrames;
    }
  }

  /// 复位:新一次评分会话前把滤波器 / 尾部 / 滑窗 / refractory 全清空,别串上次的。
  void reset() {
    _hp.reset();
    _notch1.reset();
    _notch2.reset();
    _carry = Float64List(0);
    _prevEnergy = 0;
    for (var i = 0; i < _fluxHist.length; i++) {
      _fluxHist[i] = 0;
    }
    _fluxIdx = 0;
    _fluxFilled = 0;
    _fluxSum = 0;
    _lastOnsetSec = -1e9;
    _candidateTime = null;
    _confirmFramesLeft = 0;
  }
}
