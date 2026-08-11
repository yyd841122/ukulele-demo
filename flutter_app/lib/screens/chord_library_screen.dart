// 和弦速查页:把 chordShapes 里所有和弦画成【大图】网格,点一下听它的扫弦声。
// 底导航「和弦」tab。专门给"想把某个和弦单独按熟、听准"用——跟歌练时只能看当前行的小和弦卡,
// 这里给每个和弦一张大图 + 一键试听。
//
// 关键:复用 MainScaffold 共享的 AudioEngine(连同它预加载好的扫弦声源),不在这里再起一个 SoLoud——
// 否则二次 init 引擎、再合成一遍声源,既慢又浪费。构造时把 audio 传进来,点卡只调它的 playChord。
//
// 第N步(UI 重构)重写:① 分组改用 models.dart 的 chordCategories【数据驱动】(替掉 _categoryOf
// 按和弦名 contains/endsWith 的脆弱推断,C#m / Bbmaj7 之类不再错归类);② 加【搜索框】按和弦名过滤;
// ③ 加【类别筛选 ChoiceChip】替掉原来的分组标题(选一个类别只看那一类,「全部」看所有);
// ④ 卡片改【响应式 GridView】(按屏宽自动排几列),替掉固定宽 150 的 Wrap。
import 'package:flutter/material.dart';

import '../audio/audio_engine.dart';
import '../models.dart';
import '../widgets/app_spacing.dart';
import '../widgets/chord_diagram.dart';

/// 和弦速查页:搜索 + 类别筛选 + 响应式大图网格 + 点听声。[audio] 复用共享引擎(不二次 init)。
class ChordLibraryScreen extends StatefulWidget {
  final AudioEngine audio;

  const ChordLibraryScreen({required this.audio, super.key});

  @override
  State<ChordLibraryScreen> createState() => _ChordLibraryScreenState();
}

class _ChordLibraryScreenState extends State<ChordLibraryScreen> {
  final TextEditingController _searchCtl = TextEditingController();
  String _query = '';
  // 0 = 全部;1..N = chordCategories[index-1]。
  int _categoryIndex = 0;

  // 「全部」+ 各类别名,给筛选 chip 用。
  List<String> get _chipLabels => ['全部', ...chordCategories.map((c) => c.name)];

  /// 当前要展示的和弦名列表:搜索时跨所有类别按名过滤(忽略类别选择);否则按选中的类别取。
  List<String> get _visible {
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      return chordCategories
          .expand((c) => c.chords)
          .where((n) => n.toLowerCase().contains(q))
          .toList();
    }
    if (_categoryIndex == 0) {
      return chordCategories.expand((c) => c.chords).toList();
    }
    return chordCategories[_categoryIndex - 1].chords;
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final visible = _visible;
    return Scaffold(
      appBar: AppBar(title: const Text('和弦速查')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 搜索框 + 类别筛选。
          Padding(
            padding: const EdgeInsets.fromLTRB(Spacing.s16, Spacing.s12, Spacing.s16, Spacing.s4),
            child: TextField(
              controller: _searchCtl,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: '搜索和弦名,如 C / Am / Dm7',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtl.clear();
                          setState(() => _query = '');
                        },
                      ),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(RadiusCorners.r12)),
              ),
            ),
          ),
          // 类别筛选 chip 行(横向滚动,窄屏也不挤)。搜索时仍可见但不参与过滤(搜索优先)。
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Spacing.s12),
              children: [
                for (var i = 0; i < _chipLabels.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Spacing.s4, vertical: Spacing.s4),
                    child: ChoiceChip(
                      label: Text(_chipLabels[i]),
                      selected: _categoryIndex == i && _query.isEmpty,
                      onSelected: (_) => setState(() {
                        _categoryIndex = i;
                        // 选类别时清掉搜索(避免搜索把类别过滤盖掉,造成"选了大类却看不到"的困惑)。
                        if (_query.isNotEmpty) {
                          _searchCtl.clear();
                          _query = '';
                        }
                      }),
                    ),
                  ),
              ],
            ),
          ),
          // 响应式网格:按屏宽自动排列(每格最大 ~168),替掉固定宽 150。
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Text(
                      _query.isEmpty ? '该类别没有和弦' : '没找到「$_query」相关和弦',
                      style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(Spacing.s16, Spacing.s8, Spacing.s16, Spacing.s32),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      // 200:手机约 2 列、平板约 4 列——格子够大才放得下 scale 1.5 的指法图(120 高)。
                      maxCrossAxisExtent: 200,
                      childAspectRatio: 0.95,
                      crossAxisSpacing: Spacing.s12,
                      mainAxisSpacing: Spacing.s12,
                    ),
                    itemCount: visible.length,
                    itemBuilder: (_, i) {
                      final name = visible[i];
                      return _ChordTile(
                        name: name,
                        frets: chordShapes[name]!,
                        onTap: () => widget.audio.playChord(name),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// 一张和弦卡:和弦名(上)+ 大号指法图(下)。点整张卡 → onTap。
/// 不固定宽:GridView 给多宽就填多宽(响应式)。指法图 scale 1.5(看清按弦点)。
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
      borderRadius: BorderRadius.circular(RadiusCorners.r12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: Spacing.s8, horizontal: Spacing.s4),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(RadiusCorners.r12),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                name,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.primary),
              ),
            ),
            const SizedBox(height: Spacing.s4),
            ChordDiagram(frets: frets, scale: 1.5),
          ],
        ),
      ),
    );
  }
}
