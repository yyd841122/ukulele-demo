// 跟唱录音(第49步):开麦录人声 → 攒原始 PCM16 字节 → 停时套 WAV 头给 SoLoud 回放。
//
// 跟调音器的 MicCapture 是两回事:那个把 PCM 转成 Float64 喂基频检测器、边收边丢;这个把原始
// PCM16 字节原样攒进缓冲、停时整段取走做回放。所以单独一个类,互不耦合、各管各的生命周期。
//
// 装机才能真测(权限弹窗、真麦采样)。无头环境里 record / permission 的平台通道没接 → 调用会抛
// MissingPluginException,各方法 try/catch 兜住、只打日志、返失败 / null,不崩界面(跟 MicCapture 同套路)。
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import 'audio_constants.dart';
import 'strum_synth.dart'; // buildWav:把样本套 WAV 头

/// 跟唱录音器:开麦把 PCM16 字节攒进缓冲,停时整段取走(给回放)。MVP = 只留最后一段(ephemeral)。
class VoiceRecorder {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _sub;

  bool _recording = false;
  // 攒原始 PCM16 字节(BytesBuilder 高效拼连续 chunk)。开录时清空 → 每段只留本次。
  final BytesBuilder _buf = BytesBuilder();

  /// 正在录吗(给界面切换 mic / stop 图标用)。
  bool get isRecording => _recording;

  /// 申请麦克风权限。已授权 / 刚点"允许"→ true;被拒绝 / 平台通道没接 → false。
  Future<bool> requestPermission() async {
    try {
      final status = await Permission.microphone.request();
      return status.isGranted;
    } catch (e) {
      debugPrint('录音权限申请失败: $e');
      return false;
    }
  }

  /// 被永久拒绝了?(true → 只能去系统设置开,UI 给个"去设置"按钮)
  Future<bool> isPermanentlyDenied() async {
    try {
      return (await Permission.microphone.status).isPermanentlyDenied;
    } catch (e) {
      debugPrint('查录音权限状态失败: $e');
      return false;
    }
  }

  /// 开录:清空旧缓冲、开麦、把 PCM16 字节流逐块攒进 _buf。开成功返 true。
  /// 采样率走全项目统一的 [kAudioSampleRate](跟合成 / 检测一致),单声道 PCM16。
  Future<bool> start() async {
    if (_recording) return true;
    _buf.clear();
    try {
      final stream = await _recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits, // 原始线性 PCM 16 位(没压缩、没头),直接能套 WAV 头
          sampleRate: kAudioSampleRate,
          numChannels: 1, // 单声道:人声回放单声道就够,省一半数据量
          autoGain: false,
          echoCancel: false, // 跟 MicCapture 同步:不开这些,免得动信号(回放音质靠原始数据)
          noiseSuppress: false,
        ),
      );
      _recording = true;
      _sub = stream.listen((chunk) => _buf.add(chunk));
      return true;
    } catch (e) {
      debugPrint('开录失败: $e');
      _recording = false;
      return false;
    }
  }

  /// 停录:关订阅 + 停麦,把攒到的原始 PCM16 字节整段返回(没录到 / 失败 → null)。
  /// 这里【不】套 WAV 头——只给原始字节,WAV 封装交给纯函数 wavFromPcm16(方便单独测)。
  Future<Uint8List?> stop() async {
    await _sub?.cancel();
    _sub = null;
    if (_recording) {
      try {
        await _recorder.stop();
      } catch (e) {
        debugPrint('停录失败: $e');
      }
      _recording = false;
    }
    if (_buf.isEmpty) return null;
    return _buf.takeBytes(); // 取走字节并重置(BytesBuilder 复用)
  }

  /// 释放资源(页面销毁时调):停录 + 释放 recorder(否则麦一直占着)。
  Future<void> dispose() async {
    await stop();
    await _recorder.dispose();
  }
}

/// 把原始 PCM16(单声道、小端)字节套上标准 WAV 头,返回完整 WAV(给 SoLoud loadMem 回放)。
/// 纯函数、无副作用:抽出来能在无头测试里直接锁(头标记 / 长度自洽 / 样本往返不丢)。
/// 采样率默认走 [kAudioSampleRate],跟开麦一致;复用 StrumSynth.buildWav(同一个 44 字节头布局)。
Uint8List wavFromPcm16(Uint8List pcm16, {int sampleRate = kAudioSampleRate}) {
  final bd = pcm16.buffer.asByteData(pcm16.offsetInBytes, pcm16.lengthInBytes);
  final n = pcm16.lengthInBytes ~/ 2; // 奇数尾巴丢掉(不完整样本)
  final samples = Float64List(n);
  for (var i = 0; i < n; i++) {
    samples[i] = bd.getInt16(i * 2, Endian.little) / 32768.0; // int16 → -1..1
  }
  // buildWav 内部再 ×32767 回 int16:往返丢 1 个最低位,对回放听感无影响。
  return StrumSynth.buildWav(samples, sampleRate: sampleRate);
}
