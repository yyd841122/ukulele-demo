// 扫弦合成(StrumSynth)的无头单元测试。
// 不连手机(flutter test):验证"音高算对 / WAV 字节布局对 / 峰值归一化没爆音 / 同种子确定性 / 上下扫不同"。
// 音色好不好得装机听,这里只锁"算得对不对"。
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ukulele_demo/audio/strum_synth.dart';

void main() {
  group('音高 freqForString', () {
    test('四根空弦 = 标准 GCEA', () {
      expect(StrumSynth.freqForString(0, 0), closeTo(392.00, 0.01)); // G4
      expect(StrumSynth.freqForString(1, 0), closeTo(261.63, 0.01)); // C4
      expect(StrumSynth.freqForString(2, 0), closeTo(329.63, 0.01)); // E4
      expect(StrumSynth.freqForString(3, 0), closeTo(440.00, 0.01)); // A4
    });

    test('按品升半音:12 品 = 升一个八度(频率×2)', () {
      expect(StrumSynth.freqForString(0, 12), closeTo(392.00 * 2, 0.05));
      expect(StrumSynth.freqForString(3, 12), closeTo(440.00 * 2, 0.05));
    });

    test('C 和弦 A 弦按 3 品 = C5(523.25Hz)', () {
      // chordShapes['C'] = [0,0,0,3] → A 弦(index 3)按 3 品
      expect(StrumSynth.freqForString(3, 3), closeTo(523.25, 0.05));
    });
  });

  group('WAV 字节布局', () {
    final synth = StrumSynth(seed: 1);
    final wav = synth.synthesizeStrumWav([0, 0, 0, 3]); // C 和弦下扫
    final bd = wav.buffer.asByteData();

    test('头四个标记:RIFF / WAVE / fmt / data', () {
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(String.fromCharCodes(wav.sublist(12, 16)), 'fmt ');
      expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');
    });

    test('格式字段:PCM / 单声道 / 44100Hz / 16位', () {
      expect(bd.getUint16(20, Endian.little), 1); // audioFormat = PCM
      expect(bd.getUint16(22, Endian.little), 1); // 单声道
      expect(bd.getUint32(24, Endian.little), 44100); // 采样率
      expect(bd.getUint16(34, Endian.little), 16); // 位深
      expect(bd.getUint32(28, Endian.little), 44100 * 1 * 2); // byteRate
      expect(bd.getUint16(32, Endian.little), 1 * 2); // blockAlign
    });

    test('长度字段自洽:data 长度 = 文件长 - 44;RIFF 长度 = 文件长 - 8', () {
      expect(bd.getUint32(40, Endian.little), wav.length - 44);
      expect(bd.getUint32(4, Endian.little), wav.length - 8);
    });

    test('总长 = 3 个间隔 + 单弦持续(按当前旋钮常量算)', () {
      final gap = (StrumSynth.strumGapSec * StrumSynth.sampleRate).round();
      final per = (StrumSynth.clipDuration * StrumSynth.sampleRate).round();
      final expectedSamples = gap * 3 + per;
      expect(wav.length, 44 + expectedSamples * 2);
    });
  });

  group('音质保险', () {
    test('峰值归一化:最大幅度接近满刻度、又不爆(削顶)', () {
      final wav = StrumSynth(seed: 7).synthesizeStrumWav([0, 2, 3, 2]); // G 和弦
      final bd = wav.buffer.asByteData();
      var peak = 0;
      // 扫所有 int16 样本(offset 44 起,每样本 2 字节)
      for (var p = 44; p + 1 < wav.length; p += 2) {
        final v = bd.getInt16(p, Endian.little).abs();
        if (v > peak) peak = v;
      }
      expect(peak, greaterThan(30000)); // 归一化到 0.99 → 峰值≈32439,该在 3 万以上
      expect(peak, lessThanOrEqualTo(32767)); // 不能超 int16 上限(削顶=爆音)
    });

    test('6 个和弦指法都能合成、且 WAV 自洽(不崩、长度对)', () {
      const shapes = {
        'C': [0, 0, 0, 3],
        'G': [0, 2, 3, 2],
        'Am': [2, 0, 0, 0],
        'F': [2, 0, 1, 0],
        'D': [2, 2, 2, 0],
        'Em': [0, 4, 3, 2],
      };
      for (final entry in shapes.entries) {
        final wav = StrumSynth(seed: 1).synthesizeStrumWav(entry.value);
        final bd = wav.buffer.asByteData();
        expect(bd.getUint32(40, Endian.little), wav.length - 44,
            reason: '${entry.key} 的 data 长度不自洽');
      }
    });
  });

  group('确定性 / 方向', () {
    test('同种子 → 完全相同输出(可复现)', () {
      final a = StrumSynth(seed: 42).synthesizeStrumWav([0, 0, 0, 3]);
      final b = StrumSynth(seed: 42).synthesizeStrumWav([0, 0, 0, 3]);
      expect(a, equals(b));
    });

    test('下扫 ≠ 上扫(弦的拨响顺序不同 → 混音不同)', () {
      final down = StrumSynth(seed: 42).synthesizeStrumWav([0, 0, 0, 3]);
      final up = StrumSynth(seed: 42).synthesizeStrumWav([0, 0, 0, 3], up: true);
      expect(down, isNot(equals(up)));
    });
  });
}
