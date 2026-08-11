// 首页:App 的第一屏(底导航第 0 个 tab)。
//
// 不再造一遍功能——调音 / 练琴 / 和弦 / 统计都已经是现成页面。首页是【聚合入口 / launcher】:
// 一张今日仪表盘卡(读 prefs:今日练习分钟 / 每日目标 / 连续打卡)+ 一组快捷卡片,点卡片直达对应页面。
//
// - 调音卡片:调音页已从底导航移除(每次练琴前调一次、频率低),改成这里 push 进去(全屏、返回键回首页)。
// - 练琴 / 和弦 / 统计卡片:还是底导航 tab,点卡片 = 切到底栏对应 tab(onNavigate 回调)。
//
// 今日仪表盘的数字会随练习变化,但首页在 IndexedStack 里保活、initState 只跑一次;所以
// MainScaffold 在【切回首页 tab】时调本页 reload() 重读 prefs,数字才是最新的。
import 'package:flutter/material.dart';

import '../audio/audio_engine.dart';
import '../models.dart';
import '../prefs/app_preferences.dart';
import '../theme_controller.dart';
import '../widgets/app_spacing.dart';
import 'tuner_screen.dart';

/// 首页。[audio] 用来 push 调音页;[theme] 顶栏主题切换菜单;[onNavigate] 切到底栏其它 tab。
class HomeScreen extends StatefulWidget {
  final AudioEngine audio;
  final ThemeController theme;
  final ValueChanged<int> onNavigate;

  const HomeScreen({
    required this.audio,
    required this.theme,
    required this.onNavigate,
    super.key,
  });

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  AppPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    widget.theme.addListener(_onThemeChanged); // 主题变 → 重画(顶栏图标跟上)
    _load();
  }

  @override
  void dispose() {
    widget.theme.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final p = await AppPreferences.load();
    if (!mounted) return;
    setState(() => _prefs = p);
  }

  /// 重读 prefs。给 MainScaffold 切回首页 tab 时调:首页保活,不 reload 的话读到的还是
  /// 上次的旧今日分钟,漏算这期间刚练的量。
  void reload() => _load();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('尤克里里'),
        actions: [_themeButton],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.s16),
        children: [
          _TodayCard(prefs: _prefs, onTap: () => widget.onNavigate(3)),
          const SizedBox(height: Spacing.s20),
          // 问候语
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('开始练习', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: Spacing.s4),
                Text('选一种练习方式', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(height: Spacing.s12),
          // 快捷入口:2 列卡片网格。
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: Spacing.s12,
            crossAxisSpacing: Spacing.s12,
            childAspectRatio: 1.0,
            children: [
              _HomeCard(
                icon: Icons.graphic_eq,
                title: '调音',
                subtitle: '给琴对准音高',
                color: cs.tertiaryContainer,
                onColor: cs.onTertiaryContainer,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => TunerScreen(audio: widget.audio)),
                ),
              ),
              _HomeCard(
                icon: Icons.music_note,
                title: '练琴',
                subtitle: '扫弦·换和弦·指弹·琶音',
                color: cs.primaryContainer,
                onColor: cs.onPrimaryContainer,
                onTap: () => widget.onNavigate(1),
              ),
              _HomeCard(
                icon: Icons.library_music_outlined,
                title: '和弦速查',
                subtitle: '43 个和弦指法',
                color: cs.secondaryContainer,
                onColor: cs.onSecondaryContainer,
                onTap: () => widget.onNavigate(2),
              ),
              _HomeCard(
                icon: Icons.bar_chart_outlined,
                title: '练习统计',
                subtitle: '打卡·进度·热力图',
                color: cs.surfaceContainerHighest,
                onColor: cs.onSurface,
                onTap: () => widget.onNavigate(3),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 顶栏主题切换菜单:系统 / 浅色 / 深色(当前模式打勾)。图标随当前模式变。
  Widget get _themeButton => PopupMenuButton<ThemeMode>(
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
}

/// 今日仪表盘卡:今日练习分钟 / 每日目标 + 进度条 + 连续打卡。点整张 → 统计 tab。
/// prefs 还没加载好时(_prefs == null)显示占位「—」,不卡首帧。
class _TodayCard extends StatelessWidget {
  final AppPreferences? prefs;
  final VoidCallback onTap;

  const _TodayCard({required this.prefs, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final loaded = prefs != null;
    final goalMin = loaded ? prefs!.getDailyGoalMin(30) : 30;
    final todaySec = loaded ? prefs!.getTodaySec(practiceDayKey(DateTime.now())) : 0;
    final todayMin = (todaySec / 60).round();
    final progress = goalMin > 0 ? (todayMin / goalMin).clamp(0.0, 1.0) : 0.0;
    final streak = loaded ? currentStreak(prefs!.getPracticeDays(), DateTime.now()) : 0;
    final reached = progress >= 1.0;

    return Card(
      color: cs.primaryContainer,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(RadiusCorners.r16)),
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(RadiusCorners.r16),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('今日练习', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: cs.onPrimaryContainer, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  if (streak > 0)
                    Text('🔥 $streak 天连续', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onPrimaryContainer)),
                ],
              ),
              const SizedBox(height: Spacing.s8),
              Text(
                loaded ? '$todayMin / $goalMin 分钟' : '— / $goalMin 分钟',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: cs.onPrimaryContainer, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: Spacing.s12),
              ClipRRect(
                borderRadius: BorderRadius.circular(RadiusCorners.r8),
                child: LinearProgressIndicator(
                  value: loaded ? progress : 0,
                  minHeight: 8,
                  backgroundColor: cs.onPrimaryContainer.withValues(alpha: 0.12),
                  color: reached ? cs.primary : cs.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: Spacing.s8),
              Text(
                reached ? '🎉 今日目标达成' : (streak > 0 ? '继续加油,完成今日目标' : '练一会儿,开启今天的打卡'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onPrimaryContainer),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 首页共用的「图标 + 标题 + 副标题」整卡按钮。
class _HomeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Color onColor;
  final VoidCallback onTap;

  const _HomeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(RadiusCorners.r16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(RadiusCorners.r16),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 32, color: onColor),
              const Spacer(),
              Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: onColor, fontWeight: FontWeight.w600)),
              const SizedBox(height: Spacing.s4),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: onColor), maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}
