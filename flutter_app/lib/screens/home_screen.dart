// 首页:App 的第一屏(底导航第 0 个 tab)。
//
// 不再造一遍功能——调音 / 练琴 / 和弦 / 统计都已经是现成页面。首页是【聚合入口 / launcher】:
// 一张今日仪表盘卡(Step 2 接 prefs) + 一组快捷卡片,点卡片直达对应页面。
//
// - 调音卡片:调音页已从底导航移除(每次练琴前调一次、频率低),改成这里 push 进去(全屏、返回键回首页)。
// - 练琴 / 和弦 / 统计卡片:还是底导航 tab,点卡片 = 切到底栏对应 tab(onNavigate 回调)。
import 'package:flutter/material.dart';

import '../audio/audio_engine.dart';
import '../widgets/app_spacing.dart';
import 'tuner_screen.dart';

/// 首页。[audio] 用来 push 调音页;[onNavigate] 用来切到底栏其它 tab(1 练琴 / 2 和弦 / 3 统计)。
class HomeScreen extends StatelessWidget {
  final AudioEngine audio;
  final ValueChanged<int> onNavigate;

  const HomeScreen({required this.audio, required this.onNavigate, super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('尤克里里')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 问候语(Step 2 会在下面接一张今日练习进度卡)。
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.s4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('你好 👋', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: Spacing.s4),
                  Text('今天也练一会儿吧', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(height: Spacing.s20),
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
                    MaterialPageRoute(builder: (_) => TunerScreen(audio: audio)),
                  ),
                ),
                _HomeCard(
                  icon: Icons.music_note,
                  title: '练琴',
                  subtitle: '扫弦·换和弦·指弹·琶音',
                  color: cs.primaryContainer,
                  onColor: cs.onPrimaryContainer,
                  onTap: () => onNavigate(1),
                ),
                _HomeCard(
                  icon: Icons.library_music_outlined,
                  title: '和弦速查',
                  subtitle: '43 个和弦指法',
                  color: cs.secondaryContainer,
                  onColor: cs.onSecondaryContainer,
                  onTap: () => onNavigate(2),
                ),
                _HomeCard(
                  icon: Icons.bar_chart_outlined,
                  title: '练习统计',
                  subtitle: '打卡·进度·热力图',
                  color: cs.surfaceContainerHighest,
                  onColor: cs.onSurface,
                  onTap: () => onNavigate(3),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 首页 / 练琴 Hub 共用的「图标 + 标题 + 副标题」整卡按钮。
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
