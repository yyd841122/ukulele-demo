// 麦克风采集(给真调音器用):申请录音权限 → 开麦 → 把 PCM16 字节流转成 -1..1 的 Float64 样本流,
// 给 PitchDetector 吃。封装 record 包(AudioRecorder.startStream)+ permission_handler。
//
// 只管"开/关麦 + 吐样本",不管音高(音高是 PitchDetector 的事,分开测)。也不碰 SoLoud ——
// 输入(麦克风)和输出(参考音 / 扫弦)是两套互不影响的设备,各管各的。
//
// 装机才能真测(权限弹窗、真麦采样)。无头环境里 record / permission 的平台通道没接 → 调用会抛
// MissingPluginException,各方法 try/catch 兜住、只打日志、返失败,不崩界面(跟 wakelock_plus 同一套路)。
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import 'audio_constants.dart';

class MicCapture {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _sub;

  // 对外吐样本的流(广播:可多订阅;没订阅时数据直接丢,不堆积)。
  final StreamController<Float64List> _samples =
      StreamController<Float64List>.broadcast();

  /// 每来一段 PCM 就转成 Float64(-1..1)从这里吐出去,给监听者(PitchDetector)吃。
  Stream<Float64List> get samples => _samples.stream;

  bool _recording = false;

  /// 申请麦克风权限。已授权 / 刚点"允许"→ true;被拒绝 / 永久拒绝 / 平台通道没接 → false。
  Future<bool> requestPermission() async {
    try {
      final status = await Permission.microphone.request();
      return status.isGranted;
    } catch (e) {
      debugPrint('麦克风权限申请失败: $e');
      return false;
    }
  }

  /// 被永久拒绝了?(用户勾了"不再询问"。true → 只能去系统设置开,UI 给个"去设置"按钮)
  Future<bool> isPermanentlyDenied() async {
    try {
      return (await Permission.microphone.status).isPermanentlyDenied;
    } catch (e) {
      debugPrint('查麦克风权限状态失败: $e');
      return false;
    }
  }

  /// 开麦:开始采样、把 PCM16 字节流逐块转 Float64 推到 samples 流。
  /// [sampleRate] 默认走全项目统一的 [kAudioSampleRate](跟 PitchDetector 用的一致)。开成功返 true。
  Future<bool> start({int sampleRate = kAudioSampleRate}) async {
    if (_recording) return true;
    try {
      final stream = await _recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits, // 原始线性 PCM 16 位(没压缩、没头),直接能喂检测器
          sampleRate: sampleRate,
          numChannels: 1, // 单声道:基频检测一根弦用单声道就够,还省一半数据量
          autoGain: false, // 不开自动增益:它会改信号幅度,干扰安静门判断
          echoCancel: false,
          noiseSuppress: false, // 不开降噪:它会动频谱、可能干扰音高;环境噪声靠 PitchDetector 安静门挡
        ),
      );
      _recording = true;
      _sub = stream.listen((chunk) {
        if (!_samples.isClosed) _samples.add(_pcm16ToFloat64(chunk));
      });
      return true;
    } catch (e) {
      debugPrint('开麦失败: $e');
      _recording = false;
      return false;
    }
  }

  /// 关麦。停订阅 + 停录制。幂等(没开也不报错)。
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    if (_recording) {
      try {
        await _recorder.stop();
      } catch (e) {
        debugPrint('停麦失败: $e');
      }
      _recording = false;
    }
  }

  /// PCM16 小端字节 → Float64(-1..1):每 2 字节一个 int16,除以 32768 归一化。
  /// 用 offsetInBytes/lengthInBytes 取子视图,防 chunk 是某个大缓冲的切片(开头不在 0)。
  Float64List _pcm16ToFloat64(Uint8List bytes) {
    final bd = bytes.buffer.asByteData(
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );
    final n = bytes.lengthInBytes ~/ 2; // 奇数尾巴丢掉(不完整样本)
    final out = Float64List(n);
    for (var i = 0; i < n; i++) {
      out[i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return out;
  }

  /// 释放资源(页面销毁时调):关麦 + 关控制器 + 释放 recorder(否则麦一直占着、电池掉得快)。
  Future<void> dispose() async {
    await stop();
    await _samples.close();
    await _recorder.dispose();
  }
}
