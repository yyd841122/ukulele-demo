// 和弦速查页:把 chordShapes 里所有和弦画成【大图】网格,点一下听它的扫弦声。
// 从 SongScreen 顶栏图标 Navigator.push 进来。专门给"想把某个和弦单独按熟、听准"用——
// 跟歌练时只能看当前行的小和弦卡,这里能给每个和弦一个整张大图 + 一键试听。
//
// 关键:复用 SongScreen 已 init 好的 AudioEngine(连同它预加载好的扫弦声源),不在这里再起一个 SoLoud——
// 否则二次 init 引擎、再合成一遍声源,既慢又浪费。所以构造时把 audio 传进来,点卡只调它的 playChord。
import 'package:flutter/material.dart';

import '../audio/audio_engine.dart';
import '../models.dart';
import '../widgets/chord_diagram.dart';

/// 和弦速查页:大图网格 + 点听声。[audio] 复用 SongScreen 的引擎(不二次 init)。
class ChordLibraryScreen extends StatelessWidget {
  final AudioEngine audio;

  const ChordLibraryScreen({required this.audio, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('和弦速查')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '点和弦听声音、看指法。${chordShapes.length} 个和弦。',
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            // Wrap 而不是 GridView:每张卡固定宽度、自动换行,不用猜 childAspectRatio,
            // 各种屏宽都不会溢出或压扁(跟歌词区用 Wrap 同一套思路)。
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                for (final entry in chordShapes.entries)
                  _ChordTile(
                    name: entry.key,
                    frets: entry.value,
                    onTap: () => audio.playChord(entry.key),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 一张和弦卡:和弦名(上)+ 大号指法图(中)+ "点听声"提示(下)。点整张卡 → onTap。
/// 固定宽 150,内容居中;指法图用 scale 1.5(比练习栏的参考卡大,看清按弦点)。
class _ChordTile extends StatelessWidget {
  final String name;
  final List<int> frets;
  final VoidCallback onTap;

  const _ChordTile({
    required this.name,
    required this.frets,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 150,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 4),
            ChordDiagram(frets: frets, scale: 1.5),
            const SizedBox(height: 4),
            Text(
              '👆 点听声',
              style: TextStyle(fontSize: 11, color: cs.outline),
            ),
          ],
        ),
      ),
    );
  }
}
