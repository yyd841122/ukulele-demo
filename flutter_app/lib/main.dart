// 尤克里里弹唱练习 —— Flutter 版主入口 + 歌曲页。
//
// 这一版:歌曲页能展示一首歌的"歌词 + 和弦",顶栏下拉框可切换不同歌。
// 仍为静态:不接节拍器、不自动滚动、不高亮当前和弦。
import 'package:flutter/material.dart';

import 'models.dart';

void main() {
  runApp(const UkuleleApp());
}

/// App 根部件:决定主题,把"歌曲页"设为首页。
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
      home: const SongScreen(),
    );
  }
}

/// 歌曲页:顶栏下拉选歌,正文铺出当前歌的每一段、每一行。
/// 因为要"记住当前选的是哪首",这里用 StatefulWidget(带状态),
/// 之前只显示一首时用的是 StatelessWidget。
class SongScreen extends StatefulWidget {
  const SongScreen({super.key});

  @override
  State<SongScreen> createState() => _SongScreenState();
}

class _SongScreenState extends State<SongScreen> {
  // 当前选中的歌在 songs 列表里的下标。默认第 0 首(Over the Rainbow)。
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final song = songs[_selected];
    final theme = Theme.of(context);

    // 把"段落标题(可选)+ 它的每一行"拍平成一个列表,丢进可滚动的 ListView。
    final List<Widget> items = [];
    for (final section in song.sections) {
      if (section.name != null) {
        items.add(_SectionHeader(section.name!));
      }
      for (final line in section.lines) {
        items.add(_LineView(line: line));
      }
    }

    return Scaffold(
      appBar: AppBar(
        // 标题行:选歌下拉框(独占整行宽度,不再和 BPM 抢,就不会重叠出斑马纹)。
        title: DropdownButton<int>(
          value: _selected,
          // 下拉框默认会在选中值下面画一条横线,顶栏里很难看,这里用空部件去掉。
          underline: const SizedBox.shrink(),
          // 让下拉框占满整行宽度:歌名才有地方放,而且下面的 FittedBox 才知道往多窄缩。
          isExpanded: true,
          items: [
            for (var i = 0; i < songs.length; i++)
              DropdownMenuItem(
                value: i,
                // FittedBox(scaleDown):歌名短就原样大小;太长就自动缩小字号塞进去,绝不溢出。
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    songs[i].title,
                    style: TextStyle(color: theme.colorScheme.onSurface),
                  ),
                ),
              ),
          ],
          onChanged: (i) {
            if (i != null) {
              setState(() => _selected = i);
            }
          },
          dropdownColor: theme.colorScheme.surface,
          // 下面这个 style 是"下拉框里当前显示的那行歌名"的文字样式。
          style: theme.textTheme.titleMedium
              ?.copyWith(color: theme.colorScheme.onSurface),
          icon: Icon(Icons.arrow_drop_down, color: theme.colorScheme.onSurface),
        ),
        // 第二行:速度信息。用 AppBar 的 bottom 槽放,跟标题各占一行,互不重叠。
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '${song.tempo} BPM · ${song.beatsPerChord}拍/和弦',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: items,
      ),
    );
  }
}

/// 段落标题(如"🎶 副歌")。下划线开头 = 这个部件只在本文件内用。
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
