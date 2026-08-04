// 练习统计页:把每首歌、以及全部歌的「累计遍数 / 累计时长 / 最近练到多快」列出来。
// 从 SongScreen 顶栏图标 Navigator.push 进来。数据全是 AppPreferences 里【已经存着的】
// (第22步打卡在按歌存累计遍数 + 累计秒数),这里只读、不写——所以自己 load 一份 prefs:
// SharedPreferences 是单例,读到的就是 SongScreen 写下去的最新值。
//
// 关键:进页前 SongScreen._openStats 会先把当前会话还没落盘的打卡补存
// (_accumulateSec 把这段时间结进 _totalSec、还在播就重置 _playStart 让计时不停,_saveStats 落盘),
// 这里读到的才是含「本次」的最新值,不会少算刚练的这段。
import 'package:flutter/material.dart';

import '../models.dart';
import '../prefs/app_preferences.dart';

/// 练习统计页:总计卡(跨所有歌)+ 每首歌一张卡(累计遍数 / 时长 / 原速·最近速度)。
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  AppPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _load(); // 异步读 prefs;没好之前先画 loading,不卡首帧
  }

  Future<void> _load() async {
    final p = await AppPreferences.load();
    if (!mounted) return; // 异步回来页面可能已经没了
    setState(() => _prefs = p);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final p = _prefs;
    // prefs 还没加载完:先画个 loading,加载完 setState 切过去(跟 SongScreen 首帧默认值一个套路)。
    if (p == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('练习统计')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // 总计:把所有歌的累计遍数 / 秒数相加。
    var totalLoops = 0;
    var totalSec = 0;
    for (var i = 0; i < songs.length; i++) {
      totalLoops += p.getLoops(i);
      totalSec += p.getSec(i);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('练习统计')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // 总计卡:一眼看「一共练了多少」。
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '全部练习',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$totalLoops 遍 · ${formatPracticeSec(totalSec)}',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              '按歌曲',
              style: theme.textTheme.labelLarge?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          for (var i = 0; i < songs.length; i++)
            _SongStatsCard(
              song: songs[i],
              loops: p.getLoops(i),
              sec: p.getSec(i),
              lastTempo: p.getTempo(i),
            ),
        ],
      ),
    );
  }
}

/// 一首歌的统计卡:左边歌名 + 原速/最近速度(或「还没练过」),右边累计遍数 + 时长。
class _SongStatsCard extends StatelessWidget {
  final Song song;
  final int loops;
  final int sec;
  final int? lastTempo; // 这首歌上次调到的速度(没存过 = null = 从没练到要存的程度)

  const _SongStatsCard({
    required this.song,
    required this.loops,
    required this.sec,
    required this.lastTempo,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final practiced = loops > 0 || sec > 0; // 遍数或时长有一个 > 0 就算练过
    return Card(
      color: cs.surfaceContainerHighest,
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    song.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    practiced
                        ? '原速 ${song.tempo} BPM'
                            '${lastTempo != null && lastTempo != song.tempo ? ' · 最近 $lastTempo' : ''}'
                        : '还没练过',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  practiced ? '$loops 遍' : '—',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  practiced ? formatPracticeSec(sec) : '',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
