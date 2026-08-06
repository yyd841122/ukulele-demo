// 调音页:【真调音器】听麦克风 → 测拨弦音高 → 指针表显示偏低/准/偏高;外加 G/C/E/A 参考音按钮。
//
// 两套独立的音频设备,别混:
//   - 输出(参考音):复用 MainScaffold 共享的 AudioEngine(SoLoud),点琴弦按钮听标准音。
//   - 输入(麦克风):本页自己拥有的 MicCapture(record 包),开麦后把 PCM 喂 PitchDetector(YIN)测音高。
//
// 第32步:在文本读数基础上做正式调音器——加【指针表】(cents 偏离)、【平滑】(中位数 + 漏检容忍,
// 指针不抖)、点琴弦【选目标弦】(高亮 + "这就是 X 弦/你选的是 X 但听到的是 Y" 判对)。MainScaffold
// 切走本 tab 时调 pause() 自动停麦(见 main_scaffold)。app 进后台也停(WidgetsBindingObserver)。
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
  double? _freq; // 最近一次【平滑后】的频率
  NoteResult? _note; // 最近一次【平滑后】的音名/八度/音分

  // —— 平滑用 —— 取最近几次检测的中位数当显示值,指针不抖;换弦(大跳)时清空历史、立刻跟上。
  final List<double> _recent = <double>[];
  int _misses = 0; // 连续没测到音的次数(容忍短暂漏检,免得指针一卡一显)

  String? _target; // 用户选中的"正在调这根弦":G/C/E/A;null=全自动(指针按测到的音走)

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
        _recent.clear();
        _misses = 0;
      });
    }
  }

  /// 停麦(给本页 toggle 用,也给 MainScaffold 切走 tab 时调)。幂等。
  Future<void> pause() async {
    await _sub?.cancel();
    _sub = null;
    await _mic.stop();
    _recent.clear();
    _misses = 0;
    if (mounted) {
      setState(() {
        _listening = false;
        _freq = null;
        _note = null;
      });
    }
  }

  /// 来了一段麦样本:攒进缓冲,满一窗(4096)测一次音高 → 平滑 → 刷读数。
  void _onSamples(Float64List chunk) {
    _buf.addAll(chunk);
    if (_buf.length < _window) return;
    final window = Float64List.fromList(_buf.sublist(_buf.length - _window));
    _buf.clear();
    final f = _detector.detect(window, _sampleRate);

    if (f == null) {
      // 这一窗没测到清晰音。连续 3 次(≈0.3s)才清读数,容忍偶发漏检、指针不闪。
      _misses++;
      if (_misses >= 3 && _freq != null) {
        _recent.clear();
        if (mounted) setState(() { _freq = null; _note = null; });
      }
      return;
    }

    _misses = 0;
    // 换弦(频率大跳 >~5 半音)→ 清空历史,中位数立刻跟到新弦,不拖。
    if (_recent.isNotEmpty) {
      final med = _median(_recent);
      final ratio = f > med ? f / med : med / f;
      if (ratio > 1.3) _recent.clear();
    }
    _recent.add(f);
    if (_recent.length > 7) _recent.removeAt(0);

    final smoothed = _median(_recent);
    final note = frequencyToNote(smoothed);
    if (mounted) setState(() { _freq = smoothed; _note = note; });
  }

  /// 取最近几次检测的中位数(抗偶然离群值:比平均值更不容易被一次测飞带偏)。
  double _median(List<double> xs) {
    final s = List<double>.from(xs)..sort();
    final n = s.length;
    return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
  }

  /// 某根弦"应该是什么音"(用空弦标准频率反推音名),给"选的目标弦 vs 听到的"判对用。
  NoteResult _expectedNoteFor(String name) {
    final idx = _strings.firstWhere((s) => s.name == name).idx;
    return frequencyToNote(StrumSynth.openTuning[idx]);
  }

  /// 点一根琴弦:选它做"正在调的目标"(高亮)+ 顺便播参考音(原功能)。再点同一根取消选择。
  void _selectString(String name, int idx) {
    widget.audio.playOpenString(idx);
    setState(() => _target = (_target == name) ? null : name);
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
              '选弦 · 点琴弦选「正在调这根」(也播参考音)',
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
                isSelected: _target == s.name,
                onTap: () => _selectString(s.name, s.idx),
              ),
              const SizedBox(height: 10),
            ],
            Text(
              '标准定弦 GCEA(高 G)。不选弦也行——指针按测到的音自动走。',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  /// 实时调音卡:开始/停止按钮 + (权限提示 / 未开 / 读数+指针表)。
  Widget _liveCard(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
          if (_permDenied)
            _permissionPrompt(cs)
          else if (!_listening)
            Text(
              '点「开始监听」,然后拨一下琴弦。',
              style: TextStyle(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            )
          else
            _listeningContent(cs),
        ],
      ),
    );
  }

  Widget _permissionPrompt(ColorScheme cs) {
    return Column(
      children: [
        Text('麦克风权限被永久拒绝', style: TextStyle(color: cs.error, fontSize: 15)),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => openAppSettings(),
          icon: const Icon(Icons.settings),
          label: const Text('去系统设置开启'),
        ),
      ],
    );
  }

  /// 监听中的读数:大音名 + Hz + (选了弦的话)判对 + 指针表 + 状态文字。
  Widget _listeningContent(ColorScheme cs) {
    final hasNote = _note != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              hasNote ? '${_note!.name}${_note!.octave}' : '—',
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: hasNote ? cs.primary : cs.outline,
              ),
            ),
            const SizedBox(width: 10),
            if (hasNote)
              Text(
                '${_freq!.toStringAsFixed(1)} Hz',
                style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
              ),
          ],
        ),
        if (_target != null && hasNote) ...[
          const SizedBox(height: 4),
          _matchBadge(cs),
        ],
        const SizedBox(height: 14),
        _centsMeter(cs),
        const SizedBox(height: 8),
        Text(
          hasNote
              ? _tuneLabel(_note!.cents)
              : '没听到清晰的音,拨一下弦试试。',
          style: TextStyle(
            fontSize: 13,
            color: hasNote ? _tuneColor(_note!.cents, cs) : cs.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  /// "选的目标弦" vs "听到的音" 判对。
  Widget _matchBadge(ColorScheme cs) {
    final expected = _expectedNoteFor(_target!);
    final match = _note!.name == expected.name && _note!.octave == expected.octave;
    if (match) {
      return Text(
        '✓ 这就是 $_target 弦(标准 ${expected.name}${expected.octave})',
        style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600),
      );
    }
    return Text(
      '你选的是 $_target 弦,但听到的是 ${_note!.name}${_note!.octave}',
      style: TextStyle(fontSize: 12, color: cs.error),
    );
  }

  /// 偏离指针表:中间=准,左=偏低,右=偏高。绿带是"准"区(±5 音分),针按 cents 偏移落位(±50 卡边)。
  Widget _centsMeter(ColorScheme cs) {
    final hasNote = _note != null;
    final cents = hasNote ? _note!.cents : 0.0;
    final clamped = cents.clamp(-50.0, 50.0).toDouble();
    final frac = (clamped + 50) / 100; // 0=偏低边 .. 1=偏高边,0.5=正中
    final accuracy = cents.abs();
    final Color needleColor = !hasNote
        ? cs.outline
        : accuracy < 5
            ? Colors.green
            : accuracy < 25
                ? cs.primary
                : cs.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('偏低', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            Text('准', style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w600)),
            Text('偏高', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 26,
          child: LayoutBuilder(
            builder: (ctx, c) {
              final w = c.maxWidth;
              return Stack(
                children: [
                  // 轨道
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                  ),
                  // 中间"准"绿带(±5 音分 ≈ ±5% 宽)
                  Positioned(
                    left: w * 0.45,
                    width: w * 0.10,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                  ),
                  // 正中刻度线
                  Positioned(
                    left: w * 0.5 - 1,
                    top: 0,
                    bottom: 0,
                    child: Container(width: 2, color: cs.outline),
                  ),
                  // 指针
                  if (hasNote)
                    Positioned(
                      left: (w * frac - 2).clamp(0.0, w - 4),
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 4,
                        decoration: BoxDecoration(
                          color: needleColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ],
              );
            },
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

/// 一根弦的按钮:左边大圆字母(音符)+ 中间弦名/频率 + 右边图标。[isSelected] 时高亮(选作目标)。
/// 点整行 → onTap(选目标弦 + 播参考音)。
class _StringButton extends StatelessWidget {
  final String name;
  final double freq;
  final bool isSelected;
  final VoidCallback onTap;

  const _StringButton({
    required this.name,
    required this.freq,
    required this.isSelected,
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
          color: isSelected ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? cs.primary : cs.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
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
            Icon(
              isSelected ? Icons.check_circle : Icons.volume_up,
              color: isSelected ? cs.primary : cs.outline,
            ),
          ],
        ),
      ),
    );
  }
}
