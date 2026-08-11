// 练琴 Hub:底导航「练琴」tab(第 1 个)。
//
// 把原来的 4 个平级 tab(练习 / 换和弦 / 指弹 / 琶音)合并到这一个入口下:
// 这里只做【选练习方式】,点卡片 → 全屏 push 对应练习页;返回键 pop 回这里。
//
// 全屏 push 的好处:① 练习时底导航被路由盖住,沉浸、不会误触切走;② pop 时练习页
// dispose() 自动清理(cancel 节拍器 timer / 关 wakelock / dispose 录音 / 存统计),
// 不再需要 MainScaffold 拿 GlobalKey 去"戳停"——比原来的 IndexedStack 保活 + 手动停钩子更干净。
//
// 代价:每次进入是新状态(节拍器停、从头练)。但歌曲 / 速度 / 移调从 prefs 恢复,够用。
import 'package:flutter/material.dart';

import '../audio/audio_engine.dart';
import '../song_store.dart';
import '../widgets/app_spacing.dart';
import 'arpeggio_screen.dart';
import 'chord_trainer_screen.dart';
import 'fingerpick_screen.dart';
import 'song_screen.dart';

/// 练琴入口页:选一种练习方式,全屏进入。
class PracticeHubScreen extends StatelessWidget {
  final AudioEngine audio;
  final SongStore store;

  const PracticeHubScreen({required this.audio, required this.store, super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('练琴')),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.s16),
        children: [
          _ModeCard(
            icon: Icons.music_note,
            title: '扫弦跟唱',
            subtitle: '选歌 + 节拍器 + 歌词联动和弦高亮,边弹边唱',
            color: Theme.of(context).colorScheme.primaryContainer,
            onColor: Theme.of(context).colorScheme.onPrimaryContainer,
            onTap: () => _push(context, SongScreen(audio: audio, store: store)),
          ),
          const SizedBox(height: Spacing.s12),
          _ModeCard(
            icon: Icons.fitness_center,
            title: '换和弦',
            subtitle: '两个和弦按节拍切换,5 档难度 + 60 秒挑战',
            color: Theme.of(context).colorScheme.secondaryContainer,
            onColor: Theme.of(context).colorScheme.onSecondaryContainer,
            onTap: () => _push(context, ChordTrainerScreen(audio: audio)),
          ),
          const SizedBox(height: Spacing.s12),
          _ModeCard(
            icon: Icons.piano,
            title: '指弹',
            subtitle: 'TAB 曲谱跟练:小星星 / 欢乐颂 / 卡农 …',
            color: Theme.of(context).colorScheme.tertiaryContainer,
            onColor: Theme.of(context).colorScheme.onTertiaryContainer,
            onTap: () => _push(context, FingerpickScreen(audio: audio)),
          ),
          const SizedBox(height: Spacing.s12),
          _ModeCard(
            icon: Icons.waves,
            title: '琶音',
            subtitle: '在和弦上按顺序拨弦,练伴奏织体(4321 / 4323)',
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            onColor: Theme.of(context).colorScheme.onSurface,
            onTap: () => _push(context, ArpeggioScreen(audio: audio)),
          ),
        ],
      ),
    );
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }
}

/// 一张练习方式卡:左侧图标 + 右侧标题/副标题 + 末尾箭头,点整张进对应练习页。
class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Color onColor;
  final VoidCallback onTap;

  const _ModeCard({
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
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: onColor.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: Icon(icon, color: onColor),
              ),
              const SizedBox(width: Spacing.s16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: onColor, fontWeight: FontWeight.w600)),
                    const SizedBox(height: Spacing.s4),
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: onColor), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: onColor.withValues(alpha: 0.6)),
            ],
          ),
        ),
      ),
    );
  }
}
