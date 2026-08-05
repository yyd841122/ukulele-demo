// 调音页:【真调音器】听麦克风 → 测出拨弦的音高,实时显示音名/Hz/偏高偏低;外加 G/C/E/A 参考音按钮。
//
// 两套独立的音频设备,别混:
//   - 输出(参考音):复用 MainScaffold 共享的 AudioEngine(SoLoud),点琴弦按钮听标准音 —— 跟和弦速查页同套。
//   - 输入(麦克风):本页自己拥有的 MicCapture(record 包),开麦后把 PCM 喂 PitchDetector(YIN)测音高。
//
// 第31步:先把"听得到、显示音高"跑通(文本读数:音名 + Hz + 偏高/偏低)。指针表、选弦自动对齐、
// 切走 tab 自动停麦等打磨放第32步。State 类公开 + 有 pause():第32步让 MainScaffold 切 tab 时调它停麦。
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../audio/audio_engine.dart';
import '../audio/mic_capture.dart';
import '../audio/pitch_detector.dart';
import '../audio/strum_synth.dart';

/// 四根空弦:名字 + 在 openTuning 里的下标。显示顺序 = 标准 GCEA。
const _strings = [
  (name: 'G', idx: 0),
  (name: 'C', idx: 1),
  (name: 'E', idx: 2),
  (name: 'A', idx: 3),
];

/// 调音页。[audio] 复用共享引擎放参考音;麦克风由本页自己的 MicCapture 管。
class TunerScreen extends StatefulWidget {
  final AudioEngine audio;

  const TunerScreen({required this.audio, super.key});

  @override
  State<TunerScreen> createState() => TunerScreenState();
}

class TunerScreenState extends State<TunerScreen> with WidgetsBindingObserver {
  final MicCapture _mic = MicCapture();
  // 尤克里里音域(150~500Hz)实例化:既加速、又防测到范围外的乱真峰。
  final PitchDetector _detector = const PitchDetector(
    minFrequency: 150,
    maxFrequency: 500,
  );

  static const int _sampleRate = 44100; // 跟 MicCapture / PitchDetector 用的一致
  static const int _window = 4096; // 测一次用多大缓冲(≈93ms,够尤克里里最低弦十几个周期)
  final List<double> _buf = <double>[]; // 滚动累积麦样本,攒满一窗测一次

  StreamSubscription<Float64List>? _sub; // 订阅 MicCapture 的样本流

  bool _listening = false; // 正在开麦听吗
  bool _permDenied = false; // 麦克风权限被永久拒绝了吗(只能去系统设置开)
  double? _freq; // 最近一次测到的频率
  NoteResult? _note; // 最近一次测到的音名/八度/音分

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // 监听 app 前后台:进后台要停麦
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _mic.dispose(); // async,fire-and-forget(关麦 + 释放 recorder,防麦一直占着)
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // app 进后台 / 被打断 → 关麦(隐私 + 省电)。回前台不自动续,用户自己再点开始。
    if (state != AppLifecycleState.resumed && _listening) {
      pause();
    }
  }

  /// 切「开始监听 / 停止监听」。开之前先要权限;被永久拒绝就提示去设置。
  Future<void> _toggleListening() async {
    if (_listening) {
      await pause();
      return;
    }
    final granted = await _mic.requestPermission();
    if (!granted) {
      final perm = await _mic.isPermanentlyDenied();
      if (mounted) setState(() => _permDenied = perm);
      return;
    }
    // 先订阅再开麦:broadcast 流没人听会丢事件,先挂上才不漏开头。
    _sub = _mic.samples.listen(_onSamples);
    final started = await _mic.start(sampleRate: _sampleRate);
    if (!started) {
      await _sub?.cancel();
      _sub = null;
      return;
    }
    if (mounted) {
      setState(() {
        _listening = true;
        _permDenied = false;
        _freq = null;
        _note = null;
      });
    }
  }

  /// 停麦(给本页 toggle 用,也给第32步 MainScaffold 切走 tab 时调)。幂等。
  Future<void> pause() async {
    await _sub?.cancel();
    _sub = null;
    await _mic.stop();
    if (mounted) {
      setState(() {
        _listening = false;
        _freq = null;
        _note = null;
      });
    }
  }

  /// 来了一段麦样本:攒进缓冲,满一窗(4096)就测一次音高、刷读数。
  void _onSamples(Float64List chunk) {
    _buf.addAll(chunk);
    if (_buf.length < _window) return;
    final window = Float64List.fromList(
      _buf.sublist(_buf.length - _window),
    );
    _buf.clear();
    final f = _detector.detect(window, _sampleRate);
    final note = f == null ? null : frequencyToNote(f);
    if (mounted) {
      setState(() {
        _freq = f;
        _note = note;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('调音')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _liveCard(cs),
            const SizedBox(height: 20),
            Text(
              '参考音(点琴弦听标准音)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            for (final s in _strings) ...[
              _StringButton(
                name: s.name,
                freq: StrumSynth.openTuning[s.idx],
                onTap: () => widget.audio.playOpenString(s.idx),
              ),
              const SizedBox(height: 10),
            ],
            Text(
              '标准定弦 GCEA(高 G)。参考音是拨弦声会衰减,没听清再点一下。',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  /// 实时调音卡:开始/停止按钮 + 读数(音名/Hz/偏高偏低,或权限提示)。
  Widget _liveCard(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          FilledButton.icon(
            onPressed: _toggleListening,
            icon: Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded),
            label: Text(_listening ? '停止监听' : '开始监听'),
            style: FilledButton.styleFrom(
              backgroundColor: _listening ? cs.errorContainer : cs.primary,
              foregroundColor: _listening ? cs.onErrorContainer : cs.onPrimary,
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          const SizedBox(height: 16),
          _readout(cs),
        ],
      ),
    );
  }

  /// 读数区:按 当前状态(权限/没在听/听不清/测到了)显示不同内容。
  Widget _readout(ColorScheme cs) {
    if (_permDenied) {
      return Column(
        children: [
          Text(
            '麦克风权限被永久拒绝',
            style: TextStyle(color: cs.error, fontSize: 15),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => openAppSettings(),
            icon: const Icon(Icons.settings),
            label: const Text('去系统设置开启'),
          ),
        ],
      );
    }
    if (!_listening) {
      return Text(
        '点「开始监听」,然后拨一下琴弦。',
        style: TextStyle(color: cs.onSurfaceVariant),
        textAlign: TextAlign.center,
      );
    }
    if (_note == null) {
      return Text(
        '正在听… 没听到清晰的音,拨一下弦试试。',
        style: TextStyle(color: cs.onSurfaceVariant),
        textAlign: TextAlign.center,
      );
    }
    final cents = _note!.cents;
    return Column(
      children: [
        Text(
          '${_note!.name}${_note!.octave}',
          style: TextStyle(
            fontSize: 56,
            fontWeight: FontWeight.bold,
            color: cs.primary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${_freq!.toStringAsFixed(1)} Hz',
          style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        Text(
          _tuneLabel(cents),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: _tuneColor(cents, cs),
          ),
        ),
      ],
    );
  }

  /// 音分 → 文字标签:|cents|<5 算准;否则带正负号 + 偏低/偏高。
  String _tuneLabel(double cents) {
    final sign = cents >= 0 ? '+' : '';
    final rounded = cents.toStringAsFixed(0);
    if (cents.abs() < 5) return '✓ 准  $sign$rounded 音分';
    return '$sign$rounded 音分(${cents < 0 ? '偏低' : '偏高'})';
  }

  /// 音分 → 颜色:准=绿、稍偏=主题色、偏很多=红。
  Color _tuneColor(double cents, ColorScheme cs) {
    final a = cents.abs();
    if (a < 5) return Colors.green;
    if (a < 25) return cs.primary;
    return cs.error;
  }
}

/// 一根弦的按钮:左边大圆字母(音符)+ 中间弦名/频率 + 右边喇叭图标。点整行 → onTap 播参考音。
class _StringButton extends StatelessWidget {
  final String name;
  final double freq;
  final VoidCallback onTap;

  const _StringButton({
    required this.name,
    required this.freq,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: cs.primary,
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: cs.onPrimary,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$name 弦',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${freq.toStringAsFixed(2)} Hz · 空弦标准音',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.volume_up, color: cs.primary),
          ],
        ),
      ),
    );
  }
}
