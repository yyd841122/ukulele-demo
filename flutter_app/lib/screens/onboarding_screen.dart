// 新手引导(完善Step6):首启弹 / 首页可重看的 4 页 carousel。
//
// 零基础打开不知从哪开始 → 几页图文带过一遍:抱琴 → 看懂指法图 → 按响 C → 去扫弦跟唱。
// 完成或跳过都标记 pref_onboarding_done,下次不再自动弹;首页 ? 图标随时重看。
import 'package:flutter/material.dart';

import '../audio/audio_engine.dart';
import '../models.dart'; // chordShapes
import '../widgets/app_spacing.dart';
import '../widgets/chord_diagram.dart';
import '../prefs/app_preferences.dart';

class OnboardingScreen extends StatefulWidget {
  final AudioEngine audio; // 第 3 页「听一下 C 和弦」用

  const OnboardingScreen({required this.audio, super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _ctl = PageController();
  int _page = 0;
  static const _pageCount = 4;

  /// 完成或跳过:标记 done(下次不自动弹)+ 关页。
  Future<void> _finish() async {
    final p = await AppPreferences.load();
    await p.setOnboardingDone(true);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _next() {
    if (_page >= _pageCount - 1) {
      _finish();
    } else {
      _ctl.nextPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('新手指南'),
        actions: [
          TextButton(onPressed: _finish, child: const Text('跳过')),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _ctl,
                onPageChanged: (i) => setState(() => _page = i),
                children: [_page1(cs), _page2(cs), _page3(cs), _page4(cs)],
              ),
            ),
            // 页码点(当前页加长高亮)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Spacing.s8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < _pageCount; i++) ...[
                    if (i > 0) const SizedBox(width: Spacing.s8),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: i == _page ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _page ? cs.primary : cs.outlineVariant,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // 底部导航:上一步 / 下一步(末页变「开始练习」)
            Padding(
              padding: const EdgeInsets.fromLTRB(Spacing.s16, 0, Spacing.s16, Spacing.s16),
              child: Row(
                children: [
                  if (_page > 0)
                    TextButton(
                      onPressed: () => _ctl.previousPage(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                      ),
                      child: const Text('上一步'),
                    )
                  else
                    const SizedBox(width: 72), // 占位让「下一步」始终靠右
                  const Spacer(),
                  FilledButton(
                    onPressed: _next,
                    child: Text(_page == _pageCount - 1 ? '开始练习' : '下一步'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 一页 = 一个大图 / 指法图 + 标题 + 正文(超长可滚,小屏不挤)。
  Widget _buildPage({required Widget graphic, required String title, required String body, required ColorScheme cs}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Spacing.s24, Spacing.s8, Spacing.s24, Spacing.s24),
      child: Column(
        children: [
          const SizedBox(height: Spacing.s16),
          graphic,
          const SizedBox(height: Spacing.s24),
          Text(title, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: cs.onSurface)),
          const SizedBox(height: Spacing.s12),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, height: 1.6, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _page1(ColorScheme cs) => _buildPage(
        cs: cs,
        graphic: Icon(Icons.music_note, size: 96, color: cs.primary),
        title: '先这样抱琴',
        body: '琴头朝左、琴身贴在怀里。左手按弦、右手扫弦。\n\n'
            '四根弦从右往左(对着你)是 A E C G;指法图里按 G C E A 从左到右画。\n\n'
            '先去「调音」对准音,再开始练。',
      );

  Widget _page2(ColorScheme cs) => _buildPage(
        cs: cs,
        graphic: ChordDiagram(frets: chordShapes['C']!, scale: 1.8),
        title: '看懂和弦指法图',
        body: '4 根竖线 = 4 根弦(从左到右 G C E A),横线 = 品。\n\n'
            '圆点 = 用手指按那一格;0 / ○ = 空弦(不按,直接弹响)。\n\n'
            '图里就是 C 和弦——只按最右那根(A 弦)的第 3 品。',
      );

  Widget _page3(ColorScheme cs) => _buildPage(
        cs: cs,
        graphic: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ChordDiagram(frets: chordShapes['C']!, scale: 1.8),
            const SizedBox(height: Spacing.s12),
            FilledButton.tonalIcon(
              // 无头测试环境 SoLoud 加载不了 → isReady=false → 灰;装机才听得见。
              onPressed: widget.audio.isReady ? () => widget.audio.playChord('C') : null,
              icon: const Icon(Icons.volume_up),
              label: const Text('听一下 C 和弦'),
            ),
          ],
        ),
        title: '按响第一个和弦',
        body: 'C 和弦用无名指按 A 弦第 3 品,其余弦不按。\n\n'
            '按好点「听一下」——扫出来声清脆就说明按准了。\n\n'
            '(这里播不出声是正常的,装机才听得见。)',
      );

  Widget _page4(ColorScheme cs) => _buildPage(
        cs: cs,
        graphic: Icon(Icons.play_circle_fill, size: 96, color: cs.primary),
        title: '开始第一首歌',
        body: '去「练琴」→「扫弦跟唱」,挑一首带「入门」标签的歌\n'
            '(只有 2-3 个和弦,比如 You Are My Sunshine)。\n\n'
            '按 ▶,跟着高亮的 ↓ 节拍往下扫;和弦该在哪换,歌词里会高亮告诉你。\n\n'
            '慢慢来,熟了再提速。',
      );
}
