// Karplus-Strong 拨弦合成:给定和弦指法,合成出一段扫弦声(WAV 字节)给 SoLoud 播。
//
// 纯 Dart(只依赖 dart:typed_data + dart:math),不碰 Flutter / SoLoud —— 这样能用 flutter test
// 在电脑上无头验证"音高算对、WAV 字节布局对、峰值归一化对、确定性(同种子同输出)"。
// "好不好听"得装机听(下面三个常量是听感旋钮),但"算得对不对"这里就能锁死。
//
// 原理:Karplus-Strong 是经典的拨弦物理建模——用一段长度=周期的环形缓冲装上"噪声起振",
// 然后每步取相邻两点的平均当输出并写回缓冲。这个"取平均"是个低通滤波器:高频先衰、低频拖长,
// 听上去就是拨弦那种"叮——"的衰减音。一根弦一次 _pluck;扫弦=4 根弦按顺序错开拨响再混起来。
import 'dart:math';
import 'dart:typed_data';

class StrumSynth {
  // —— 听感旋钮(装机听后可调)——
  static const int sampleRate = 44100; // 必须跟 WAV 头里的 byteRate 对上
  static const double clipDuration = 0.8; // 每根弦拨响后衰减多长(秒)。长了在快歌会糊;短了干巴。
  static const double strumGapSec = 0.030; // 弦与弦错开多久(秒)= 扫弦的"颗粒感"。太小像一块和弦,太大像琶音。
  static const double decay = 0.996; // KS 衰减系数(<1 衰减更快)。越大余音越长。

  // 尤克里里标准 GCEA(高 G 弦 / re-entrant)四根空弦频率。
  // 顺序 = chordShapes 里 frets 数组的弦顺序(G C E A),所以 frets[i] 直接配 openTuning[i],不用换序。
  static const List<double> openTuning = [392.00, 261.63, 329.63, 440.00];

  final Random _random;

  /// [seed] 给定时,合成结果完全确定(测试用);不传则每次随机起振(更像真琴,每次扫弦略不同)。
  StrumSynth({int? seed}) : _random = seed == null ? Random() : Random(seed);

  /// 第 stringIndex 根弦(G=0,C=1,E=2,A=3)按第 fret 品的频率。
  /// 每品升一个半音 = 频率 ×2^(1/12)。
  static double freqForString(int stringIndex, int fret) {
    return (openTuning[stringIndex] * pow(2, fret / 12)).toDouble();
  }

  /// Karplus-Strong 拨一根频率为 [freq] 的弦,返回该弦的衰减波形(Float64,长度 = durationSec×sampleRate)。
  /// [durationSec] 默认跟扫弦一样(0.8s);调音参考音会传更长的(余音多响一会儿、好边听边拧弦钮)。
  Float64List _pluck(double freq, {double durationSec = clipDuration}) {
    final n = max(1, (sampleRate / freq).round()); // 环形缓冲长 = 一个周期采样数(至少 1)
    final buf = Float64List(n);
    for (var i = 0; i < n; i++) {
      buf[i] = _random.nextDouble() * 2 - 1; // 白噪声起振
    }
    final total = (durationSec * sampleRate).round();
    final out = Float64List(total);
    var idx = 0;
    for (var s = 0; s < total; s++) {
      out[s] = buf[idx]; // 先取当前缓冲值当输出(教科书 KS:输出在更新前)
      final nxt = (idx + 1) % n;
      buf[idx] = decay * (buf[idx] + buf[nxt]) / 2; // 再"取相邻平均 + 衰减"写回 → 低通=衰减引擎
      idx = nxt;
    }
    // 末尾 10ms 线性淡出,保证收尾归零、不"咔"一下(直流跳变=咔哒底噪)。
    final fade = (0.010 * sampleRate).round();
    for (var s = 0; s < fade; s++) {
      out[total - fade + s] *= s / fade;
    }
    return out;
  }

  /// 给定和弦指法 frets(GCEA 顺序,0=空弦),合成一段扫弦的完整 WAV(44字节头 + 单声道16位PCM)。
  /// up=false(下扫):弦按物理顺序 G→C→E→A 依次拨响(模拟拨片从上往下扫过琴弦);
  /// up=true(上扫):A→E→C→G。
  Uint8List synthesizeStrumWav(List<int> frets, {bool up = false}) {
    final gapSamples = (strumGapSec * sampleRate).round();
    final perString = (clipDuration * sampleRate).round();
    // 总长 = 第 4 根弦(最晚)等 3 个间隔才开始 + 它自己持续 perString。
    final total = gapSamples * 3 + perString;
    final mix = Float64List(total);

    final order = up ? const [3, 2, 1, 0] : const [0, 1, 2, 3]; // 下扫 G→A,上扫 A→G
    for (var k = 0; k < 4; k++) {
      final stringIdx = order[k];
      final tone = _pluck(freqForString(stringIdx, frets[stringIdx]));
      final offset = k * gapSamples;
      for (var s = 0; s < perString; s++) {
        mix[offset + s] += tone[s];
      }
    }

    // 4 根弦叠加后峰值可能到 ~4.0;峰值归一化到 0.99,避免转 int16 时削顶(削顶=爆音)。
    var peak = 0.0;
    for (final v in mix) {
      final a = v.abs();
      if (a > peak) peak = a;
    }
    if (peak > 0) {
      final g = 0.99 / peak;
      for (var i = 0; i < mix.length; i++) {
        mix[i] *= g;
      }
    }

    return buildWav(mix, sampleRate: sampleRate);
  }

  /// 合成【单根空弦】的拨弦声(给"调音参考音"用):拨第 stringIndex 根空弦(fret=0),套 WAV 头返回。
  /// 和扫弦用的是同一个 _pluck 引擎 + 同一个 buildWav 头——区别只在扫弦拨四根错开叠起来,
  /// 这边只拨一根,听上去是"叮——"的单音,正好拿来做调音基准(拿你琴上拨出的声跟它对)。
  /// [durationSec] 默认跟扫弦一样;调音页在 AudioEngine 里传更长的(见 referenceToneSec)。
  Uint8List synthesizeOpenStringWav(int stringIndex, {double durationSec = clipDuration}) {
    final tone = _pluck(openTuning[stringIndex], durationSec: durationSec);
    // 单弦没叠 4 根、峰值约 1.0;归一化到 0.99 顶满音量 + 防意外削顶(跟扫弦同一套保险)。
    var peak = 0.0;
    for (final v in tone) {
      final a = v.abs();
      if (a > peak) peak = a;
    }
    if (peak > 0) {
      final g = 0.99 / peak;
      for (var i = 0; i < tone.length; i++) {
        tone[i] *= g;
      }
    }
    return buildWav(tone, sampleRate: sampleRate);
  }

  /// 把 Float64 样本(-1..1)套上标准 WAV 头(44字节)+ 单声道 16位 PCM,返回完整 WAV 字节。
  /// 布局跟 assets/click.wav 完全一致(44 头 + PCM),所以 SoLoud 的 loadMem 能直接吃。
  /// 设成 static + 公开:测试要单独验"字节布局对不对",不和合成逻辑绑死。
  static Uint8List buildWav(
    Float64List samples, {
    int sampleRate = 44100,
    int channels = 1,
    int bitsPerSample = 16,
  }) {
    final bytesPerSample = bitsPerSample ~/ 8;
    final dataBytes = samples.length * bytesPerSample * channels;
    final out = Uint8List(44 + dataBytes);
    final bd = out.buffer.asByteData();
    var p = 0;

    void tag(String t) {
      final c = t.codeUnits;
      out[p] = c[0];
      out[p + 1] = c[1];
      out[p + 2] = c[2];
      out[p + 3] = c[3];
      p += 4;
    }

    void u32(int v) {
      bd.setUint32(p, v, Endian.little);
      p += 4;
    }

    void u16(int v) {
      bd.setUint16(p, v, Endian.little);
      p += 2;
    }

    tag('RIFF');
    u32(36 + dataBytes); // 文件大小 - 8
    tag('WAVE');
    tag('fmt ');
    u32(16); // PCM 子块长度
    u16(1); // audioFormat = 1 = PCM
    u16(channels);
    u32(sampleRate);
    u32(sampleRate * channels * bytesPerSample); // byteRate
    u16(channels * bytesPerSample); // blockAlign
    u16(bitsPerSample);
    tag('data');
    u32(dataBytes);
    // PCM:int16,裁剪到 [-32768, 32767](归一化后理论上不裁,这里兜底防意外)。
    for (var i = 0; i < samples.length; i++) {
      var v = (samples[i] * 32767).round();
      if (v > 32767) v = 32767;
      if (v < -32768) v = -32768;
      bd.setInt16(p, v, Endian.little);
      p += 2;
    }
    return out;
  }
}
