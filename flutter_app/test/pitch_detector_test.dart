// 基频检测(PitchDetector / frequencyToNote)的无头单元测试。
// 不连手机(flutter test):喂一段已知频率的纯正弦波,看测回来的频率对不对;喂静音 / 太短 / 极小声
// 看是不是乖乖返回 null。再锁 frequencyToNote 的音名 / 八度 / 音分。
// 算法"认得准不准"得装机拿真琴试(真琴有泛音 + 环境噪声,比纯正弦难),但"算法对不对"这里就能锁死。
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ukulele_demo/audio/pitch_detector.dart';

/// 生成一段指定频率的纯正弦波(幅度 1.0),给 detect 测。
Float64List _sine(double freq, int n, int sampleRate) {
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = sin(2 * pi * freq * i / sampleRate);
  }
  return out;
}

void main() {
  const sr = 44100;
  const n = 4096; // ≈93ms,够覆盖尤克里里最低弦(Low-G ~196Hz)两个以上周期
  const det = PitchDetector(minFrequency: 150, maxFrequency: 500); // 尤克里里范围

  group('已知频率的正弦波 → 测回原频率', () {
    test('四根空弦 GCEA 都测得准(±1Hz)', () {
      expect(det.detect(_sine(392.00, n, sr), sr), closeTo(392.00, 1.0)); // G4
      expect(det.detect(_sine(261.63, n, sr), sr), closeTo(261.63, 1.0)); // C4
      expect(det.detect(_sine(329.63, n, sr), sr), closeTo(329.63, 1.0)); // E4
      expect(det.detect(_sine(440.00, n, sr), sr), closeTo(440.00, 1.0)); // A4
    });

    test('Low-G(196Hz,降八度 G 弦)也能测', () {
      expect(det.detect(_sine(196.00, n, sr), sr), closeTo(196.00, 1.0));
    });

    test('非整数频率(弦略微跑调)能测回', () {
      // A 弦偏低 10 cents ≈ 437.4Hz(440 × 2^(-10/1200))
      final flat = (440 * pow(2, -10 / 1200)).toDouble();
      expect(det.detect(_sine(flat, n, sr), sr), closeTo(flat, 1.0));
    });
  });

  group('测不到的情况 → 返回 null', () {
    test('静音(全零)', () {
      expect(det.detect(Float64List(n), sr), isNull);
    });

    test('极小幅度(被安静门挡)', () {
      final quiet = _sine(440, n, sr);
      for (var i = 0; i < quiet.length; i++) {
        quiet[i] *= 0.001; // 幅度 0.001,均方 5e-7 < 1e-4
      }
      expect(det.detect(quiet, sr), isNull);
    });

    test('缓冲太短(覆盖不到最低频率)', () {
      expect(det.detect(_sine(440, 32, sr), sr), isNull);
    });

    // 注:频率【范围外】的纯正弦不保证返回 null —— YIN 在卡死的 τ 窗口里可能撞上谐波周期、
    // 报出一个窗口内的乱真音高。这是有界搜索的固有行为,不算 bug;所以这里不测范围外 → null。
    // 范围外的【真信号】由 UI 层用"和目标弦差太多就忽略"再挡一道(第37步已补:见 TunerScreen
    // _closeToTarget + 这里的 centsBetween)。
  });

  group('frequencyToNote 音名/八度/音分', () {
    test('四根空弦的音名 + 八度', () {
      expect(frequencyToNote(440.00).name, 'A');
      expect(frequencyToNote(440.00).octave, 4);
      expect(frequencyToNote(261.63).name, 'C');
      expect(frequencyToNote(261.63).octave, 4);
      expect(frequencyToNote(329.63).name, 'E');
      expect(frequencyToNote(329.63).octave, 4);
      expect(frequencyToNote(392.00).name, 'G');
      expect(frequencyToNote(392.00).octave, 4);
    });

    test('准的音 cents ≈ 0(容差放宽到 1.5:四舍五入的标准频率本身就和精确值差零点几音分)', () {
      expect(frequencyToNote(440.00).cents, closeTo(0, 1.5));
      expect(frequencyToNote(261.63).cents, closeTo(0, 1.5));
    });

    test('偏高 cents > 0、偏低 cents < 0', () {
      // 445Hz 比 A4(440)高约 +19.6 cents,音名仍认作 A4。
      final sharp = frequencyToNote(445);
      expect(sharp.name, 'A');
      expect(sharp.octave, 4);
      expect(sharp.cents, greaterThan(15));
      expect(sharp.cents, lessThan(25));
      // 430Hz 比 A4 低约 -40 cents,仍认作 A4。
      final flat = frequencyToNote(430);
      expect(flat.name, 'A');
      expect(flat.cents, lessThan(-30));
    });

    test('升半音名 A#4(466.16Hz)', () {
      final bb = frequencyToNote(466.16);
      expect(bb.name, 'A#');
      expect(bb.octave, 4);
      expect(bb.cents, closeTo(0, 0.5));
    });

    test('A4 校准:同一频率在不同 a4 下音分不同、音名不变', () {
      // 440Hz 在 a4=440(标准)→ A4,准(≈0 音分)
      final std = frequencyToNote(440, a4: 440);
      expect(std.name, 'A');
      expect(std.octave, 4);
      expect(std.cents, closeTo(0, 0.5));
      // 440Hz 在 a4=442(交响音高)→ 比 442 低约 -7.9 音分(偏低),仍认作 A4
      final flat = frequencyToNote(440, a4: 442);
      expect(flat.name, 'A');
      expect(flat.octave, 4);
      expect(flat.cents, lessThan(-5));
      expect(flat.cents, greaterThan(-15));
      // 442Hz 在 a4=442 → 准(≈0);在 a4=440 → 偏高约 +7.9
      expect(frequencyToNote(442, a4: 442).cents, closeTo(0, 0.5));
      expect(frequencyToNote(442, a4: 440).cents, greaterThan(5));
    });
  });

  group('centsBetween(弦距过滤用)', () {
    test('同频 = 0 音分', () {
      expect(centsBetween(440, 440), closeTo(0, 0.01));
    });

    test('高八度 = +1200、低八度 = -1200(八度误报典型:把 A4 听成 A3)', () {
      expect(centsBetween(880, 440), closeTo(1200, 0.01)); // A5 vs A4
      expect(centsBetween(220, 440), closeTo(-1200, 0.01)); // A3 vs A4 ← 八度误报
    });

    test('相邻空弦间距:纯四度 ≈ 500、大三度 ≈ 400(都比 600 阈值小,该放行)', () {
      expect(centsBetween(261.63, 196.00), closeTo(500, 5)); // C4 vs G3:纯四度
      expect(centsBetween(329.63, 261.63), closeTo(400, 5)); // E4 vs C4:大三度
    });
  });
}
