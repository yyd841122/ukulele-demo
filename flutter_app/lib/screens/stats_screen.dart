// 练习统计页:把每首歌、以及全部歌的「累计遍数 / 累计时长 / 最近练到多快」列出来。
// 第28步起是底导航的一个 tab(和练习页平级)。数据全是 AppPreferences 里【已经存着的】
// (第22步打卡在按歌存累计遍数 + 累计秒数),这里只读、不写——所以自己 load 一份 prefs:
// SharedPreferences 是单例,读到的就是 SongScreen 写下去的最新值。
//
// 关键:练习页切走时 MainScaffold 会调它的 flushStats 把当前会话还没落盘的打卡补存
// (_accumulateSec 把这段时间结进 _totalSec、还在播就重置 _playStart 让计时不停,_saveStats 落盘),
// 再调本页 reload() 重读——这样读到的才是含「本次」的最新值,不会少算刚练的这段。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Clipboard:备份一键复制 / 导入粘贴
import 'package:share_plus/share_plus.dart'; // 系统分享面板:把备份文本一键发出去(第50步)

import '../audio/reminder_service.dart'; // 练习提醒(第58步-4)
import '../models.dart';
import '../prefs/app_preferences.dart';
import '../song_backup.dart'; // encodeBackup / decodeBackup(第50步)
import '../song_store.dart';
import '../theme_controller.dart';

/// 练习统计页:总计卡(跨所有歌)+ 每首歌一张卡(累计遍数 / 时长 / 原速·最近速度)。
///
/// 第28步起和练习页是底导航的平级 tab(IndexedStack 保活):一次 initState 后 State 常驻,
/// 切回统计 tab 不会重跑 initState。所以 MainScaffold 在切到统计 tab 时会调 reload() 重读 prefs,
/// 读到的才是含「本次练习」的最新值(练习 tab 切走时已先 flushStats 把当前会话刷盘)。
class StatsScreen extends StatefulWidget {
  final SongStore store; // 歌单(内置 + 用户自加);加 / 删用户歌时刷新"按歌曲"列表
  final ThemeController theme; // 主题控制器(第47步):顶栏菜单切 系统/浅色/深色

  const StatsScreen({required this.store, required this.theme, super.key});

  @override
  State<StatsScreen> createState() => StatsScreenState();
}

/// public:MainScaffold 持 `GlobalKey<StatsScreenState>`,切到统计 tab 时调 reload()。
class StatsScreenState extends State<StatsScreen> {
  /// 歌单(内置 + 用户自加)。从歌库读——加 / 删用户歌后"按歌曲"列表能跟上。
  List<Song> get songs => widget.store.songs;

  AppPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChanged); // 歌单变 → 重读 + 重画按歌列表
    widget.theme.addListener(_onThemeChanged); // 主题变 → 重画(图标跟上当前模式)
    _load(); // 异步读 prefs;没好之前先画 loading,不卡首帧
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    widget.theme.removeListener(_onThemeChanged);
    super.dispose();
  }

  /// 歌单变了(加 / 删用户歌):重读 prefs + setState 重画(build 里的 songs getter 会拿到新歌单)。
  void _onStoreChanged() {
    if (!mounted) return;
    _load();
  }

  // 主题变了 → 重画一下,让顶栏主题按钮的图标跟上当前模式。
  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  // 顶栏主题切换菜单:系统 / 浅色 / 深色,当前模式打勾。PopupMenuButton 的图标也随当前模式变。
  PopupMenuButton<ThemeMode> get _themeButton => PopupMenuButton<ThemeMode>(
        icon: Icon(_themeIcon(widget.theme.value)),
        tooltip: '主题',
        onSelected: (m) => widget.theme.set(m),
        itemBuilder: (_) => [
          for (final m in const [ThemeMode.system, ThemeMode.light, ThemeMode.dark])
            CheckedPopupMenuItem<ThemeMode>(
              value: m,
              checked: widget.theme.value == m,
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(_themeLabel(m)),
              ),
            ),
        ],
      );

  static IconData _themeIcon(ThemeMode m) => switch (m) {
        ThemeMode.system => Icons.brightness_auto,
        ThemeMode.light => Icons.light_mode_outlined,
        ThemeMode.dark => Icons.dark_mode_outlined,
      };
  static String _themeLabel(ThemeMode m) => switch (m) {
        ThemeMode.system => '跟随系统',
        ThemeMode.light => '浅色',
        ThemeMode.dark => '深色',
      };

  Future<void> _load() async {
    final p = await AppPreferences.load();
    if (!mounted) return; // 异步回来页面可能已经没了
    setState(() => _prefs = p);
  }

  /// 重新读一遍 prefs。给 MainScaffold 在切到统计 tab 时调:tab 平级后 initState 只跑一次,
  /// 不 reload 的话读到的还是上次切来时的旧值,漏算这期间在练习 tab 刚练的量。
  void reload() => _load();

  // 顶栏备份 / 导入菜单(第50步):把用户自加歌导出 JSON 文本(复制 / 分享),或从文本导回。
  // 备份 / 导入只对【用户自加歌】有意义(内置歌在代码里),用 store.songs + isUserSong 取。
  PopupMenuButton<String> get _backupButton => PopupMenuButton<String>(
        icon: const Icon(Icons.cloud_upload_outlined),
        tooltip: '备份 / 导入歌曲',
        onSelected: (v) {
          if (v == 'backup') {
            _exportSongs();
          } else if (v == 'import') {
            _importSongs();
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'backup', child: Text('备份 / 分享我的歌')),
          PopupMenuItem(value: 'import', child: Text('从备份导入歌')),
        ],
      );

  /// 备份:把用户自加歌编码成 JSON 文本,弹框给用户【复制到剪贴板】或【分享…】出去。
  /// 没有用户歌 → 直接提示,不开框。
  Future<void> _exportSongs() async {
    final userSongs = [
      for (final s in songs)
        if (widget.store.isUserSong(s)) s,
    ];
    if (userSongs.isEmpty) {
      _toast('还没有自己加的歌,不用备份');
      return;
    }
    final backup = encodeBackup(userSongs);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('备份 ${userSongs.length} 首歌'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '下面是 ${userSongs.length} 首自加歌的备份文本。复制或分享出去,换手机 / 重装时粘到「从备份导入」就能恢复。',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                // 备份文本可能很长:限高 200 可滚、可选(也能手动选中复制)。
                SizedBox(
                  height: 200,
                  child: Scrollbar(
                    child: SingleChildScrollView(
                      child: SelectableText(
                        backup,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: backup));
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                _toast('已复制 ${userSongs.length} 首歌到剪贴板');
              },
              child: const Text('复制到剪贴板'),
            ),
            FilledButton.icon(
              onPressed: () => SharePlus.instance.share(
                ShareParams(text: backup, subject: '我的尤克里里练习歌'),
              ),
              icon: const Icon(Icons.share_outlined),
              label: const Text('分享…'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  /// 导入:粘贴备份文本 → 解析 → 确认 → 加到歌库末尾(分配新 id,不动现有歌)。
  Future<void> _importSongs() async {
    final ctl = TextEditingController();
    String? err; // 解析出错时的文案(TextField 的 errorText)
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSt) {
            return AlertDialog(
              title: const Text('从备份导入歌'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '把备份文本整段粘进来。会加到歌库末尾,不影响现有歌(重复导入会重复加,可之后删)。',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: ctl,
                      maxLines: 8,
                      minLines: 4,
                      decoration: InputDecoration(
                        hintText: '在这里粘贴备份文本…',
                        border: const OutlineInputBorder(),
                        errorText: err,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () async {
                    final text = ctl.text.trim();
                    if (text.isEmpty) {
                      setSt(() => err = '先把备份文本粘进来');
                      return;
                    }
                    try {
                      final parsed = decodeBackup(text);
                      if (parsed.isEmpty) {
                        setSt(() => err = '没解析到歌,文本对吗?');
                        return;
                      }
                      final confirmed = await _confirmImport(parsed.length);
                      if (confirmed != true) return;
                      widget.store.addAll(parsed);
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      _toast('导入了 ${parsed.length} 首歌');
                    } on FormatException catch (e) {
                      setSt(() => err = e.message.isEmpty ? '解析失败,文本对吗?' : e.message);
                    }
                  },
                  child: const Text('导入'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 导入前的二次确认(告诉用户会加几首,免得误粘进东西)。
  Future<bool?> _confirmImport(int n) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认导入'),
        content: Text('把 $n 首歌加到歌库末尾?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('导入'),
          ),
        ],
      ),
    );
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final p = _prefs;
    // prefs 还没加载完:先画个 loading,加载完 setState 切过去(跟 SongScreen 首帧默认值一个套路)。
    if (p == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('练习统计'),
          actions: [_backupButton, _themeButton],
        ),
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
      appBar: AppBar(
        title: const Text('练习统计'),
        actions: [_backupButton, _themeButton],
      ),
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

          // 每日目标卡(第58步-3):今天练了多少 vs 目标
          _DailyGoalCard(p: p),
          const SizedBox(height: 12),

          // 练习提醒卡(第58步-4):开关+时间设置
          _ReminderCard(p: p),
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
              lastPracticed: p.getLastPracticed(songs[i].id),
            ),
        ],
      ),
    );
  }
}

/// 一首歌的统计卡:左边歌名 + 原速/最近速度 + 上次练习(或「还没练过」),右边累计遍数 + 时长。
class _SongStatsCard extends StatelessWidget {
  final Song song;
  final int loops;
  final int sec;
  final int? lastTempo;
  final String? lastPracticed; // ISO 日期字符串 'yyyy-MM-dd'(第55步)

  const _SongStatsCard({
    required this.song,
    required this.loops,
    required this.sec,
    required this.lastTempo,
    required this.lastPracticed,
  });

  /// 把 ISO 日期字符串折成中文"上次:今天/昨天/N天前/还没练过"。
  String _lastPracticeLabel(String? iso) {
    if (iso == null) return '还没练过';
    final d = DateTime.tryParse(iso);
    if (d == null) return '还没练过';
    final today = DateTime.now();
    final daysAgo = DateTime(today.year, today.month, today.day)
        .difference(DateTime(d.year, d.month, d.day))
        .inDays;
    if (daysAgo == 0) return '上次: 今天';
    if (daysAgo == 1) return '上次: 昨天';
    return '上次: $daysAgo 天前';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final practiced = loops > 0 || sec > 0;
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
                        ? '${_lastPracticeLabel(lastPracticed)} · '
                            '原速 ${song.tempo} BPM'
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
      children: [
        // 星期标签(第55步):左边一列 一二三四五六日
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final l in ['一', '二', '三', '四', '五', '六', '日'])
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: Center(
                      child: Text(
                        l,
                        style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        ...columns,
      ],
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

/// 练习提醒卡(第58步-4):开关 + 时间选择,改完立刻同步到系统通知。
class _ReminderCard extends StatefulWidget {
  final AppPreferences p;
  const _ReminderCard({required this.p});

  @override
  State<_ReminderCard> createState() => _ReminderCardState();
}

class _ReminderCardState extends State<_ReminderCard> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final enabled = widget.p.getReminderEnabled();
    final hour = widget.p.getReminderHour(19);
    final minute = widget.p.getReminderMinute(0);
    final timeLabel = '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🔔', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '练习提醒',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Switch(
                value: enabled,
                onChanged: (v) async {
                  if (v) {
                    // Android 13+ 先请求通知权限
                    await ReminderService().requestPermission();
                  }
                  widget.p.setReminderEnabled(v);
                  await ReminderService().sync(widget.p);
                  setState(() {});
                },
              ),
            ],
          ),
          if (enabled)
            GestureDetector(
              onTap: () => _pickTime(context, hour, minute),
              child: Row(
                children: [
                  const SizedBox(width: 30),
                  Icon(Icons.access_time, size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    '每天 $timeLabel',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '点此改时间',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickTime(BuildContext context, int hour, int minute) async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: hour, minute: minute),
    );
    if (time == null) return;
    widget.p.setReminderHour(time.hour);
    widget.p.setReminderMinute(time.minute);
    await ReminderService().sync(widget.p);
    setState(() {});
  }
}

/// 每日练习目标卡(第58步-3):今天练了多久 vs 目标,线性进度条 + 设置入口。
class _DailyGoalCard extends StatelessWidget {
  final AppPreferences p;
  const _DailyGoalCard({required this.p});

  /// 弹对话框设目标:10/20/30/45/60 分钟,点完立刻存。
  void _showGoalDialog(BuildContext context) {
    final goal = p.getDailyGoalMin(30);
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('每日练琴目标'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '目标: $goal 分钟',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(ctx).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [10, 20, 30, 45, 60]
                    .map((m) => ChoiceChip(
                          label: Text('$m 分'),
                          selected: goal == m,
                          onSelected: (_) {
                            p.setDailyGoalMin(m);
                            Navigator.pop(ctx);
                          },
                        ))
                    .toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final goalMin = p.getDailyGoalMin(30);
    final today = practiceDayKey(DateTime.now());
    final todaySec = p.getTodaySec(today);
    final todayMin = (todaySec / 60).round();
    final progress = goalMin > 0 ? (todayMin / goalMin).clamp(0.0, 1.0) : 0.0;
    final reached = progress >= 1.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: reached ? cs.primaryContainer : cs.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: GestureDetector(
        onTap: () => _showGoalDialog(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  reached ? '🎉' : '🎯',
                  style: const TextStyle(fontSize: 22),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    reached ? '今日目标达成!' : '今日目标',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: reached ? cs.onPrimaryContainer : cs.onTertiaryContainer,
                    ),
                  ),
                ),
                Icon(Icons.settings_outlined, size: 18,
                    color: reached ? cs.onPrimaryContainer : cs.onTertiaryContainer),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '今天练了 ${formatPracticeSec(todaySec)} / 目标 $goalMin 分钟',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: reached ? cs.onPrimaryContainer : cs.onTertiaryContainer,
              ),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: (reached ? cs.onPrimaryContainer : cs.onTertiaryContainer).withValues(alpha: 0.2),
                valueColor: AlwaysStoppedAnimation<Color>(
                  reached ? cs.onPrimaryContainer : cs.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
