// 和弦速查页:把 chordShapes 里所有和弦画成【大图】网格,点一下听它的扫弦声。
// 从 SongScreen 顶栏图标 Navigator.push 进来。专门给"想把某个和弦单独按熟、听准"用——
// 跟歌练时只能看当前行的小和弦卡,这里能给每个和弦一个整张大图 + 一键试听。
//
// 关键:复用 SongScreen 已 init 好的 AudioEngine(连同它预加载好的扫弦声源),不在这里再起一个 SoLoud——
// 否则二次 init 引擎、再合成一遍声源,既慢又浪费。所以构造时把 audio 传进来,点卡只调它的 playChord。
//
// 第55步:加分组标题(大三/小三/属七/大七/小七/sus4/sus2/dim/aug),去每卡"点听声"提示。
import 'package:flutter/material.dart';

import '../audio/audio_engine.dart';
import '../models.dart';
import '../widgets/chord_diagram.dart';

/// 按和弦名推断类别(中文标签)。
String _categoryOf(String name) {
  if (name.contains('maj7')) return '大七和弦 (Major 7th)';
  if (name.contains('m7')) return '小七和弦 (Minor 7th)';
  if (name.endsWith('7') && !name.contains('maj') && !name.contains('m')) return '属七和弦 (Dominant 7th)';
  if (name.contains('sus4')) return '挂四和弦 (sus4)';
  if (name.contains('sus2')) return '挂二和弦 (sus2)';
  if (name.contains('dim')) return '减和弦 (dim)';
  if (name.contains('aug')) return '增和弦 (aug)';
  if (name.endsWith('m') && name.length <= 3) return '小三和弦 (Minor)';
  return '大三和弦 (Major)';
}

/// 和弦速查页:大图网格 + 分组标题 + 点听声。[audio] 复用 SongScreen 的引擎(不二次 init)。
class ChordLibraryScreen extends StatelessWidget {
  final AudioEngine audio;

  const ChordLibraryScreen({required this.audio, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 把 chordShapes 按键分组,每组画标题 + Wrap
    final entries = chordShapes.entries.toList();
    final groups = <(String, List<MapEntry<String, List<int>>>)>[];
    String? current;
    List<MapEntry<String, List<int>>> currentEntries = [];
    for (final e in entries) {
      final cat = _categoryOf(e.key);
      if (current != cat) {
        if (current != null) groups.add((current, currentEntries));
        current = cat;
        currentEntries = [e];
      } else {
        currentEntries.add(e);
      }
    }
    if (current != null) groups.add((current, currentEntries));

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
            const SizedBox(height: 8),
            for (final (cat, entries) in groups) ...[
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 8),
                child: Text(
                  cat,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  for (final entry in entries)
                    _ChordTile(
                      name: entry.key,
                      frets: entry.value,
                      onTap: () => audio.playChord(entry.key),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 一张和弦卡:和弦名(上)+ 大号指法图(中)。点整张卡 → onTap。
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
          ],
        ),
      ),
    );
  }
}
