// 添加 / 编辑自己的歌(第43b步:添加;第43c步:编辑回填)。
// 表单:歌名 + 速度 + 歌词(带和弦)。歌词框下面一排 6 个和弦按钮,点一下在【光标处】插 [X],
// 不用手敲方括号——这是第43步定下的输入法(门槛低、又能精确落和弦到词)。
//
// 保存校验:① 歌名非空;② 至少一行歌词;③ 歌词里所有 [和弦] 都是 chordShapes 认识的
//    (C G Am F D Em)——否则练习页画指法图取 chordShapes[name]! 会崩,这里挡掉并提示。
// 空行分段:歌词里空一行 = 新段落(方便分主歌 / 副歌),没空行就是单段。
//
// 不直接写歌库:校验通过 pop 回传一个 Song,调用方(练习页)拿去 store.add / update。
import 'dart:math';

import 'package:flutter/material.dart';

import '../models.dart';

/// 添加 / 编辑自己的歌。[initial] = null 添加模式;非 null 编辑模式(回填 + 保留 id)。
class AddSongScreen extends StatefulWidget {
  final Song? initial;

  const AddSongScreen({this.initial, super.key});

  @override
  State<AddSongScreen> createState() => _AddSongScreenState();
}

class _AddSongScreenState extends State<AddSongScreen> {
  late final TextEditingController _titleCtl;
  late final TextEditingController _lyricsCtl;
  late int _tempo;
  late int _beatsPerChord; // 每和弦持续几拍(默认 4);第44步起用户可在表单选 2/3/4/6/8

  // 每和弦几拍的可选项。4 = 最常见(4/4,一小节一个和弦);3 = 华尔兹(3/4);2 = 换得快;
  // 6/8 = 一个和弦拖更久。海岛/民谣/摇滚这些招牌节奏按 4 拍写,选别的拍数能练、扫弦形状自动截断。
  static const _beatChoices = [2, 3, 4, 6, 8];

  // 可插入的和弦 = chordShapes 里那 6 个(C G Am F D Em);插进歌词后指法图才画得出。
  late final List<String> _chords = chordShapes.keys.toList();

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    _titleCtl = TextEditingController(text: init?.title ?? '');
    // 编辑模式:把已有段落拍回成带 [和弦] 的文本;有段落名的段前面加一行 #名字(跟 parseLyrics 对得上)。
    _lyricsCtl = TextEditingController(
      text: init == null
          ? ''
          : [
              for (final s in init.sections)
                [
                  if (s.name != null && s.name!.isNotEmpty) '#${s.name}',
                  ...s.lines.map((l) => l.lyric),
                ].join('\n'),
            ].join('\n\n'),
    );
    _tempo = init?.tempo ?? 80;
    _beatsPerChord = init?.beatsPerChord ?? 4; // 编辑回填这首歌的拍数;新增默认 4
  }

  @override
  void dispose() {
    _titleCtl.dispose();
    _lyricsCtl.dispose();
    super.dispose();
  }

  /// 点一个和弦按钮:在光标处插 [和弦](有选区就替换选区);光标无效就插末尾。
  void _insertChord(String chord) {
    final c = _lyricsCtl;
    final sel = c.selection;
    final lo = sel.isValid ? min(sel.baseOffset, sel.extentOffset) : c.text.length;
    final hi = sel.isValid ? max(sel.baseOffset, sel.extentOffset) : c.text.length;
    final insert = '[$chord]';
    c.value = TextEditingValue(
      text: c.text.replaceRange(lo, hi, insert),
      selection: TextSelection.collapsed(offset: lo + insert.length),
    );
  }

  /// 把歌词文本拆成段落(空行分段、#名字 命名)的逻辑抽到了 models.parseLyrics——这里直接用。

  /// 保存:校验 → 拼成 Song → pop 回传。校验不过弹 SnackBar 提示、不退出。
  void _save() {
    final title = _titleCtl.text.trim();
    if (title.isEmpty) {
      _toast('先填个歌名吧');
      return;
    }
    final sections = parseLyrics(_lyricsCtl.text);
    if (sections.isEmpty) {
      _toast('歌词不能空:至少写一行');
      return;
    }
    // 校验歌词里所有 [和弦] 都认识——否则练习页画指法图会取 null 崩,这里挡掉。
    final used = RegExp(r'\[([^\]]+)\]')
        .allMatches(_lyricsCtl.text)
        .map((m) => m.group(1)!)
        .toSet();
    final unknown = used.where((c) => !chordShapes.containsKey(c)).toList()..sort();
    if (unknown.isNotEmpty) {
      _toast('和弦 ${unknown.join(' / ')} 还不支持,只能用:${_chords.join(' ')}');
      return;
    }
    Navigator.of(context).pop(Song(
      id: widget.initial?.id ?? '', // 编辑保留原 id;添加留空(歌库 add 时分配 'u<n>')
      title: title,
      tempo: _tempo,
      beatsPerChord: _beatsPerChord,
      sections: sections,
    ));
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final editing = widget.initial != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? '编辑歌' : '添加自己的歌'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: '保存',
            onPressed: _save,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _titleCtl,
              decoration: const InputDecoration(
                labelText: '歌名',
                hintText: '如:我的歌',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            // 速度
            Row(
              children: [
                const Text('速度'),
                Expanded(
                  child: Slider(
                    min: 40,
                    max: 200,
                    divisions: 160, // 一档 1 BPM
                    value: _tempo.toDouble(),
                    label: '$_tempo BPM',
                    onChanged: (v) => setState(() => _tempo = v.round()),
                  ),
                ),
                SizedBox(width: 48, child: Text('$_tempo', textAlign: TextAlign.end)),
              ],
            ),
            const SizedBox(height: 12),
            // 每和弦几拍:一个和弦持续几拍后换下一个。4 拍最常见(一小节一个和弦);华尔兹(3/4)选 3;
            // 和弦换得快选 2;拖久点选 6/8。招牌节奏(海岛/民谣/摇滚)按 4 拍写的,别的拍数能练、
            // 扫弦形状会自动截断(不崩,只是少几下);全下/下上任何拍数都正常。
            Row(
              children: [
                const Text('每和弦几拍'),
                const SizedBox(width: 12),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final b in _beatChoices)
                        ChoiceChip(
                          label: Text('$b'),
                          selected: _beatsPerChord == b,
                          onSelected: (_) => setState(() => _beatsPerChord = b),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '歌词与和弦:换行分句、空行分段;行首写 #副歌 给段落命名;点和弦按钮在光标处插 [X]',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            // 和弦插入按钮(点一下插到歌词框光标处)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in _chords)
                  ElevatedButton(onPressed: () => _insertChord(c), child: Text(c)),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _lyricsCtl,
              maxLines: 12,
              minLines: 6,
              decoration: const InputDecoration(
                hintText: '#主歌\n[C]第一句 [G]...\n\n#副歌\n[Am]高潮 [F]...',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '只能用这几个和弦:${_chords.join('  ')}',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
