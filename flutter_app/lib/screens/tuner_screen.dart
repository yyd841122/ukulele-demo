// 调音页:G/C/E/A 四根空弦的参考音按钮。点一下听标准音,把你琴上对应弦调到一样高。
//
// 关键:复用 MainScaffold 共享的 AudioEngine(跟和弦速查页同一套)——不在这里再起一个 SoLoud,
// 只调它的 playOpenString。参考音是 AudioEngine 启动时用 Karplus-Strong 拨弦合成预生成的,
// 跟扫弦同一个引擎,只是拨一根(听上去是"叮——"的单音,适合拿来做调音基准)。
//
// 显示顺序 G C E A = 尤克里里标准弦序(从上到下四根弦);频率直接读 StrumSynth.openTuning,
// 跟合成用的频率同源,不会出现"显示的 Hz 和实际播的对不上"。
import 'package:flutter/material.dart';

import '../audio/audio_engine.dart';
import '../audio/strum_synth.dart';

/// 四根空弦:名字 + 在 openTuning 里的下标。显示顺序 = 标准 GCEA。
const _strings = [
  (name: 'G', idx: 0),
  (name: 'C', idx: 1),
  (name: 'E', idx: 2),
  (name: 'A', idx: 3),
];

/// 调音页:G/C/E/A 参考音按钮。[audio] 复用共享引擎(不二次 init)。
class TunerScreen extends StatelessWidget {
  final AudioEngine audio;

  const TunerScreen({required this.audio, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('调音')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '点琴弦听标准音,把你琴上对应弦调到一样高。标准定弦 GCEA(高 G)。',
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            for (final s in _strings) ...[
              _StringButton(
                name: s.name,
                freq: StrumSynth.openTuning[s.idx],
                onTap: () => audio.playOpenString(s.idx),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 4),
            Text(
              '提示:参考音是拨弦声、会自然衰减;没听清就再点一下。建议从 A 弦(440Hz)开始对。',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
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
