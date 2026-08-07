// 练习统计页:把每首歌、以及全部歌的「累计遍数 / 累计时长 / 最近练到多快」列出来。
// 第28步起是底导航的一个 tab(和练习页平级)。数据全是 AppPreferences 里【已经存着的】
// (第22步打卡在按歌存累计遍数 + 累计秒数),这里只读、不写——所以自己 load 一份 prefs:
// SharedPreferences 是单例,读到的就是 SongScreen 写下去的最新值。
//
// 关键:练习页切走时 MainScaffold 会调它的 flushStats 把当前会话还没落盘的打卡补存
// (_accumulateSec 把这段时间结进 _totalSec、还在播就重置 _playStart 让计时不停,_saveStats 落盘),
// 再调本页 reload() 重读——这样读到的才是含「本次」的最新值,不会少算刚练的这段。
import 'package:flutter/material.dart';

import '../models.dart';
import '../prefs/app_preferences.dart';

/// 练习统计页:总计卡(跨所有歌)+ 每首歌一张卡(累计遍数 / 时长 / 原速·最近速度)。
///
/// 第28步起和练习页是底导航的平级 tab(IndexedStack 保活):一次 initState 后 State 常驻,
/// 切回统计 tab 不会重跑 initState。所以 MainScaffold 在切到统计 tab 时会调 reload() 重读 prefs,
/// 读到的才是含「本次练习」的最新值(练习 tab 切走时已先 flushStats 把当前会话刷盘)。
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => StatsScreenState();
}

/// public:MainScaffold 持 `GlobalKey<StatsScreenState>`,切到统计 tab 时调 reload()。
class StatsScreenState extends State<StatsScreen> {
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

  /// 重新读一遍 prefs。给 MainScaffold 在切到统计 tab 时调:tab 平级后 initState 只跑一次,
  /// 不 reload 的话读到的还是上次切来时的旧值,漏算这期间在练习 tab 刚练的量。
  void reload() => _load();

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
      totalLoops += p.getLoops(songs[i].id);
      totalSec += p.getSec(songs[i].id);
    }

    // 练习日历:哪天练过(跨歌)→ 算连续打卡天数 + 画日历热力图。
    final practicedDays = p.getPracticeDays();
    final practicedSet = practicedDays.toSet();
    final now = DateTime.now();
    final streak = currentStreak(practicedDays, now);

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

          // 连续打卡卡:🔥 连续 N 天 + 累计 M 天(激励向,放总计下面最显眼)。
          // 用 secondaryContainer 跟总计卡 primaryContainer 区分开。
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: cs.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Text('🔥', style: TextStyle(fontSize: 30)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '连续练琴 $streak 天',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: cs.onSecondaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '累计练琴 ${practicedSet.length} 天',
                        style: TextStyle(fontSize: 12, color: cs.onSecondaryContainer),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 日历热力图:最近 13 周(≈3 个月),深色 = 练过。横向往左是更早的周。
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              '最近 13 周(深色 = 练过)',
              style: theme.textTheme.labelLarge?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          _PracticeCalendar(practiced: practicedSet, today: now, weeks: 13),
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
              loops: p.getLoops(songs[i].id),
              sec: p.getSec(songs[i].id),
              lastTempo: p.getTempo(songs[i].id),
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

/// 练习日历热力图:最近 [weeks] 周,7 行(周一..周日)× N 列(周)。
/// 深色方块 = 那天练过、浅色 = 没练、空白 = 未来(还没到)。横向从左(更早)到右(本周)。
/// 对齐:每列是一个完整自然周(周一..周日);本周可能只有到今天为止的几天,后面留空。
class _PracticeCalendar extends StatelessWidget {
  final Set<String> practiced; // practiceDayKey('yyyy-MM-dd') 集合
  final DateTime today;
  final int weeks;

  const _PracticeCalendar({
    required this.practiced,
    required this.today,
    this.weeks = 13,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final todayDate = DateTime(today.year, today.month, today.day); // 折成零点,比较用
    // 本周的周一:weekday 1=周一..7=周日,所以减 (weekday-1) 天。
    final daysSinceMon = todayDate.weekday - 1;
    final thisMonday = todayDate.subtract(Duration(days: daysSinceMon));
    // 整个窗口的左上角 = 本周周一往前推 (weeks-1) 周。
    final firstMonday = thisMonday.subtract(Duration(days: (weeks - 1) * 7));

    final columns = <Widget>[];
    for (var w = 0; w < weeks; w++) {
      final colChildren = <Widget>[];
      for (var d = 0; d < 7; d++) {
        final date = firstMonday.add(Duration(days: w * 7 + d));
        if (colChildren.isNotEmpty) colChildren.add(const SizedBox(height: 3));
        colChildren.add(_dayCell(cs, date, todayDate));
      }
      columns.add(
        Padding(
          padding: EdgeInsets.only(right: w == weeks - 1 ? 0 : 3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: colChildren,
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: columns,
    );
  }

  /// 一个日期方格:练过 = 主色实心、没练 = 浅灰、未来 = 透明(占位不画色)。
  Widget _dayCell(ColorScheme cs, DateTime date, DateTime todayDate) {
    const size = 14.0;
    if (date.isAfter(todayDate)) {
      // 未来日子:留空格占位(保持网格对齐),不涂色。
      return const SizedBox(width: size, height: size);
    }
    final did = practiced.contains(practiceDayKey(date));
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: did ? cs.primary : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}
