// 尤克里里弹唱练习 —— Flutter 版主入口 + 歌曲页。
//
// 这一版是【超薄切片】:把一首歌的"歌词 + 和弦"静态铺出来,
// 先不接节拍器、不自动滚动、不高亮当前和弦。
// 目标是在手机上亲眼看到"真正的尤克里里内容"用 Flutter 渲染出来 —— 证明构建链路能交付真东西。
import 'package:flutter/material.dart';

import 'models.dart';

void main() {
  runApp(const UkuleleApp());
}

/// App 根部件:决定主题,并把"歌曲页"设为首页。
class UkuleleApp extends StatelessWidget {
  const UkuleleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '尤克里里弹唱练习',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // 深色主题,观感对齐 Web 版 PWA;seedColor 决定整体配色基调。
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C8EE3), // 偏蓝紫,呼应"彩虹"主题
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const SongScreen(song: sampleSong),
    );
  }
}

/// 歌曲页:把一首歌的每一段、每一行铺出来。
/// 每一行 = 上面一排和弦"贴片" + 下面一行歌词。
class SongScreen extends StatelessWidget {
  final Song song;

  const SongScreen({super.key, required this.song});

  @override
  Widget build(BuildContext context) {
    // 把"段落标题(可选)+ 它的每一行"拍平成一个列表,丢进可滚动的 ListView。
    // (这一步 ListView 还不会自己滚 —— 留给后面"自动滚动"切片。)
    final List<Widget> items = [];
    for (final section in song.sections) {
      if (section.name != null) {
        items.add(_SectionHeader(section.name!));
      }
      for (final line in section.lines) {
        items.add(_LineView(line: line));
      }
    }

    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(song.title),
        // 顶部右上角显示速度信息(只展示,这一步还不能调)。
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '${song.tempo} BPM · ${song.beatsPerChord}拍/和弦',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: items,
      ),
    );
  }
}

/// 段落标题(如"🎵 接着那段..."、"🎶 副歌")。下划线开头 = 这个部件只在本文件内用。
class _SectionHeader extends StatelessWidget {
  final String name;

  const _SectionHeader(this.name);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(
        name,
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 一行:上面一排和弦贴片,下面是歌词。
class _LineView extends StatelessWidget {
  final Line line;

  const _LineView({required this.line});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 和弦行:每个和弦一个小贴片。用 Wrap 是为了窄屏(手机)能自动换行,不会溢出报错。
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [for (final c in line.chords) _ChordChip(c)],
          ),
          const SizedBox(height: 4),
          // 歌词
          Text(line.lyric, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}

/// 单个和弦贴片:圆角小色块 + 和弦名。
class _ChordChip extends StatelessWidget {
  final String chord;

  const _ChordChip(this.chord);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.primary, width: 1),
      ),
      child: Text(
        chord,
        style: TextStyle(
          color: cs.onPrimaryContainer,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }
}
