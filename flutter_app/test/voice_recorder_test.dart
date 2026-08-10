// 跟唱录音的纯函数 wavFromPcm16 无头单元测试(不连手机)。
// 录音器(VoiceRecorder)本身走平台通道(record 包 + 麦克风),无头环境跑不了 → 这里只锁「PCM16 字节
// 套出来的 WAV 头对、长度自洽、单声道 16 位」,跟 strum_synth_test 一个套路。装机才验真能录能放。
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ukulele_demo/audio/voice_recorder.dart';

void main() {
  group('wavFromPcm16 头部 + 长度', () {
    // 8 个 PCM16 样本(16 字节):交替正负满刻度,便于看往返。
    final bd = ByteData(16);
    for (var i = 0; i < 8; i++) {
      bd.setInt16(i * 2, i.isEven ? 32000 : -32000, Endian.little);
    }
    final pcm = bd.buffer.asUint8List();
    final wav = wavFromPcm16(pcm);
    final wbd = wav.buffer.asByteData();

    test('头四个标记:RIFF / WAVE / fmt / data', () {
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(String.fromCharCodes(wav.sublist(12, 16)), 'fmt ');
      expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');
    });

    test('格式字段:PCM / 单声道 / 44100Hz / 16 位', () {
      expect(wbd.getUint16(20, Endian.little), 1); // PCM
      expect(wbd.getUint16(22, Endian.little), 1); // 单声道
      expect(wbd.getUint32(24, Endian.little), 44100); // 采样率
      expect(wbd.getUint16(34, Endian.little), 16); // 位深
    });

    test('长度自洽:data 长度 = 原始 PCM 字节数;总长 = 44 + data', () {
      expect(wbd.getUint32(40, Endian.little), pcm.length); // data 区 = 输入字节
      expect(wav.length, 44 + pcm.length);
      expect(wbd.getUint32(4, Endian.little), wav.length - 8); // RIFF 长度
    });
  });

  group('wavFromPcm16 边界', () {
    test('空输入不崩:只返回 44 字节头、data 长度 0', () {
      final wav = wavFromPcm16(Uint8List(0));
      expect(wav.length, 44);
      expect(wav.buffer.asByteData().getUint32(40, Endian.little), 0);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    });

    test('奇数个字节:尾巴 1 字节丢掉(data 长度取偶)', () {
      final pcm = Uint8List.fromList([1, 2, 3]); // 1.5 个样本
      final wav = wavFromPcm16(pcm);
      // 只有第 1 个完整样本(2 字节)进 data;尾巴 1 字节丢。
      expect(wav.buffer.asByteData().getUint32(40, Endian.little), 2);
      expect(wav.length, 44 + 2);
    });
  });
}
