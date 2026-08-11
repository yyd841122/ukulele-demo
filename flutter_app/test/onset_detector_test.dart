// 扫弦起始检测(OnsetDetector + Biquad)的无头单元测试。
// 不连手机(flutter test):用合成的信号喂检测器,看 onset 检得对不对、嗒声(880/1320Hz)滤得干不干净。
// "真琴吵不吵、检得稳不稳"得装机拿真琴试,但"算法对不对 + 滤波链够不够狠"这里就能锁死
// (跟 pitch_detector_test / strum_synth_test 一个套路:合成信号锁算法)。
//
// 关键回归:滤波链必须把嘀声嗒声(880/1320Hz)压到 ≥40dB,且不误伤扫弦(宽带噪声 burst)。
// 这是整套「跟弹评分」的承重墙——压不掉嗒声,每拍都会被当扫弦 → 分数虚高。
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ukulele_demo/audio/onset_detector.dart';

const _sr = 44100;

/// 纯音(可选开头淡入,避免阶跃起振产生宽带溅射 —— 模拟"一直在响"的稳态嗒声)。
Float64List _sine(double freq, int n, {double amp = 0.3, double fadeInSec = 0}) {
  final out = Float64List(n);
  final fadeN = (fadeInSec * _sr).round();
  final omega = 2 * pi * freq / _sr;
  for (var i = 0; i < n; i++) {
    final atk = (fadeN > 0 && i < fadeN) ? (i / fadeN) : 1.0; // 线性淡入
    out[i] = amp * sin(omega * i) * atk;
  }
  return out;
}

/// 一段总长 N 的信号,在指定时刻放若干个【衰减宽带噪声 burst】(像扫弦)。
/// burst = 白噪声 × 指数衰减包络(≈50ms e-folding)。返回的信号其它位置为 0(静音)。
Float64List _strumBursts(int n, List<({double at, double amp})> bursts, {double decaySec = 0.05}) {
  final out = Float64List(n);
  final rng = Random(12345); // 固定种子:可复现
  final decayN = (decaySec * _sr).round();
  for (final b in bursts) {
    final start = (b.at * _sr).round();
    final durN = (0.25 * _sr).round(); // 每个 burst 持续 250ms(衰减后基本归零)
    for (var i = 0; i < durN; i++) {
      final idx = start + i;
      if (idx < 0 || idx >= n) continue;
      final env = exp(-i / decayN);
      out[idx] += b.amp * (rng.nextDouble() * 2 - 1) * env;
    }
  }
  return out;
}

/// 一串「带淡入的短嘀声」(像评分时节拍器嗒声):每 [periodSec] 一个 [durSec] 长的 880Hz 短音,开头淡入。
/// 用来验证:真实场景下重复出现的嗒声不会被当成扫弦。
Float64List _beepTrain(int n, {double freq = 880, double periodSec = 0.75, double durSec = 0.03, double amp = 0.3}) {
  final out = Float64List(n);
  final fadeN = (0.004 * _sr).round(); // 4ms 淡入(跟评分嗒声一致)
  final omega = 2 * pi * freq / _sr;
  final periodN = (periodSec * _sr).round();
  final durN = (durSec * _sr).round();
  for (var t = 0; t < n; t += periodN) {
    for (var i = 0; i < durN && t + i < n; i++) {
      final env = exp(-i / (0.006 * _sr)); // 6ms 衰减(跟 _synthesizeClick 一致)
      final atk = i < fadeN ? 0.5 * (1 - cos(pi * i / fadeN)) : 1.0;
      out[t + i] = amp * sin(omega * i) * env * atk;
    }
  }
  return out;
}

/// 把整段信号当【一个 chunk】喂检测器,arrivalSec = n/sr(使样本 i 的时刻 = i/sr)。
/// 返回检出的 onset 时刻列表(秒)。
List<double> _runOnce(Float64List sig) {
  final det = OnsetDetector(sampleRate: _sr);
  return det.process(sig, sig.length / _sr);
}

double _rms(Float64List s, int start, int end) {
  var sum = 0.0;
  for (var i = start; i < end; i++) {
    sum += s[i] * s[i];
  }
  return sqrt(sum / (end - start));
}

/// dB 衰减量(负数,越负滤得越狠):20·log10(out/in)。
double _attenDb(double inRms, double outRms) => 20 * log(outRms / inRms) / log(10);

void main() {
  group('静音 / 基本检出', () {
    test('纯静音 → 无 onset', () {
      expect(_runOnce(Float64List(44100)), isEmpty);
    });

    test('单个扫弦 burst(0.3s)→ 检到一个 onset,在 0.3s 附近(±50ms)', () {
      final sig = _strumBursts(44100, [(at: 0.3, amp: 0.3)]);
      final onsets = _runOnce(sig);
      expect(onsets.length, 1);
      expect(onsets.first, closeTo(0.3, 0.05));
    });

    test('两个 burst 间隔 0.4s(> refractory)→ 检到两个', () {
      final sig = _strumBursts(44100, [
        (at: 0.3, amp: 0.3),
        (at: 0.7, amp: 0.3),
      ]);
      final onsets = _runOnce(sig);
      expect(onsets.length, 2);
      expect(onsets[0], closeTo(0.3, 0.05));
      expect(onsets[1], closeTo(0.7, 0.05));
    });

    test('两个 burst 间隔 0.05s(< refractory 120ms)→ 只检到一个', () {
      final sig = _strumBursts(44100, [
        (at: 0.3, amp: 0.3),
        (at: 0.35, amp: 0.3),
      ]);
      final onsets = _runOnce(sig);
      expect(onsets.length, 1);
    });
  });

  group('嗒声剔除(承重墙)', () {
    test('稳态 880Hz 纯音(像嘀声,带淡入防爆溅)→ 滤波后无 onset', () {
      final sig = _sine(880, 44100, amp: 0.3, fadeInSec: 0.05);
      expect(_runOnce(sig), isEmpty);
    });

    test('稳态 1320Hz 纯音(重音嘀声)→ 无 onset', () {
      final sig = _sine(1320, 44100, amp: 0.3, fadeInSec: 0.05);
      expect(_runOnce(sig), isEmpty);
    });

    test('重复的短嘀声(像评分节拍器,每 0.75s 一个)→ 无 onset', () {
      // 这是真实场景:评分时节拍器嗒声。压不掉它 = 每拍假阳 = 分数虚高。
      final sig = _beepTrain(44100 * 2, freq: 880, periodSec: 0.75);
      expect(_runOnce(sig), isEmpty);
    });

    test('【最关键】扫弦 burst + 同时叠 880Hz 纯音 → onset 在 burst 处、不在纯音处', () {
      // 信号 = 全程稳态 880 嗒声 + 一个 0.3s 的扫弦 burst。该只检出 0.3s 那一下。
      final tone = _sine(880, 44100, amp: 0.3, fadeInSec: 0.05);
      final sig = _strumBursts(44100, [(at: 0.3, amp: 0.3)]);
      for (var i = 0; i < sig.length; i++) {
        sig[i] += tone[i];
      }
      final onsets = _runOnce(sig);
      expect(onsets.length, 1, reason: '只该检出扫弦那一下,嗒声那一路应被滤掉。实际:$onsets');
      expect(onsets.first, closeTo(0.3, 0.05));
    });
  });

  group('滤波链衰减量 ≥40dB(量化锁鲁棒性)', () {
    test('880Hz 经过 HP150→notch880→notch1320,稳态衰减 ≤ -40dB', () {
      final chain = [
        Biquad.highpass(150, _sr),
        Biquad.notch(880, _sr),
        Biquad.notch(1320, _sr),
      ];
      final sig = _sine(880, 44100, amp: 0.5);
      final inRms = _rms(sig, 22050, 44100); // 后半段(稳态,避开滤波器起振)
      for (final b in chain) {
        b.processInPlace(sig);
      }
      final outRms = _rms(sig, 22050, 44100);
      expect(_attenDb(inRms, outRms), lessThan(-40.0),
          reason: '880Hz 应被陷波器深深压掉,实际衰减 ${_attenDb(inRms, outRms).toStringAsFixed(1)}dB');
    });

    test('1320Hz(重音)同样衰减 ≤ -40dB', () {
      final chain = [
        Biquad.highpass(150, _sr),
        Biquad.notch(880, _sr),
        Biquad.notch(1320, _sr),
      ];
      final sig = _sine(1320, 44100, amp: 0.5);
      final inRms = _rms(sig, 22050, 44100);
      for (final b in chain) {
        b.processInPlace(sig);
      }
      final outRms = _rms(sig, 22050, 44100);
      expect(_attenDb(inRms, outRms), lessThan(-40.0),
          reason: '1320Hz(重音嘀声)应被压掉,实际衰减 ${_attenDb(inRms, outRms).toStringAsFixed(1)}dB');
    });
  });

  group('幅度动态范围', () {
    test('轻扫(amp 0.1)也检得到', () {
      final sig = _strumBursts(44100, [(at: 0.4, amp: 0.1)]);
      final onsets = _runOnce(sig);
      expect(onsets.length, 1);
      expect(onsets.first, closeTo(0.4, 0.05));
    });
  });

  group('跨 chunk 状态连续', () {
    test('把信号拆成多个小 chunk 喂 → 检出的 onset 仍在 burst 附近(滤波器/拼帧状态跨 chunk 正确)', () {
      final sig = _strumBursts(44100, [(at: 0.55, amp: 0.3)]);
      final det = OnsetDetector(sampleRate: _sr);
      final onsets = <double>[];
      const chunkN = 1000; // 拆成 44 段,每段 ~23ms(不是 hop 整数倍 → 会触发拼帧)
      var consumed = 0;
      while (consumed < sig.length) {
        final end = (consumed + chunkN).clamp(0, sig.length);
        final chunk = Float64List.sublistView(sig, consumed, end);
        // 这段末样本的时刻(秒)
        final arrival = end / _sr;
        onsets.addAll(det.process(chunk, arrival));
        consumed = end;
      }
      expect(onsets.length, 1);
      expect(onsets.first, closeTo(0.55, 0.06));
    });
  });
}
