// 尤克里里弹唱练习 —— 数据模型。
//
// 概念叫法统一见仓库根目录 CONTEXT.md:
//   Song(歌曲) → Section(段落) → Line(歌词行) → Chord(和弦)
//
// 这个文件【只放数据长什么样】(+ 一个把"带和弦标记的歌词"拆成段的纯函数),不放界面。界面在 main.dart。
// 加新歌只是往下面的 songs 列表里再加一条,界面自动跟上。
//
// 和弦位置:歌词里用 [C] 这种方括号标在"该弹的那个词"前面(行内和弦 / ChordPro 风格)。
// 例:"[C]Somewhere over the [G]rainbow" = 弹 C 时唱 Somewhere、弹 G 时唱 rainbow。
// 这比 Web 版(和弦单独一排、不和具体词挂钩)对新手更友好,是 Flutter 版刻意改的。
import 'package:flutter/foundation.dart';

/// 行内解析出来的一段:要么是一个和弦(chord 非空),要么是一截歌词文字。
/// 给界面按顺序画"和弦贴片 + 文字"用。
@immutable
class InlineToken {
  final String? chord; // 非 null = 这是一个和弦标记
  final String text; // 歌词文字(和弦 token 时为空)

  const InlineToken._({this.chord, this.text = ''});
  bool get isChord => chord != null;
}

/// 把 "[C]word [G]next" 拆成 token 序列(和弦与文字交替)。
/// 例:"[C]Somewhere [G]over" → [chord:C, text:"Somewhere ", chord:G, text:"over"]
List<InlineToken> parseInline(String marked) {
  final tokens = <InlineToken>[];
  final re = RegExp(r'\[([^\]]+)\]'); // 匹配 [和弦]
  var last = 0;
  for (final m in re.allMatches(marked)) {
    if (m.start > last) {
      tokens.add(InlineToken._(text: marked.substring(last, m.start)));
    }
    tokens.add(InlineToken._(chord: m.group(1)));
    last = m.end;
  }
  if (last < marked.length) {
    tokens.add(InlineToken._(text: marked.substring(last)));
  }
  return tokens;
}

/// 一个歌词词 + 可能挂在它上方的和弦。给"和弦浮在词上方、按词排"的画法用。
@immutable
class WordUnit {
  final String? chord; // 这个词上方的和弦(null = 无)
  final String word;

  const WordUnit({this.chord, required this.word});
  bool get hasChord => chord != null;
}

/// 把 "[C]词 [G]词 词" 拆成词单元:和弦挂到它后面紧跟的第一个词上,其余词无和弦。
/// 例:"[C]Somewhere [G]over the" → [C|Somewhere, G|over, -|the]
List<WordUnit> parseWords(String marked) {
  final tokens = parseInline(marked);
  final units = <WordUnit>[];
  String? pending; // 还没挂到词上的和弦
  for (final t in tokens) {
    if (t.isChord) {
      if (pending != null) {
        units.add(WordUnit(chord: pending, word: '')); // 连续和弦:前一个挂空词,别丢
      }
      pending = t.chord;
    } else {
      final words = t.text
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .toList();
      for (var i = 0; i < words.length; i++) {
        units.add(WordUnit(chord: i == 0 ? pending : null, word: words[i]));
        if (i == 0) pending = null; // 第一个词挂完就清空
      }
    }
  }
  if (pending != null) {
    units.add(WordUnit(chord: pending, word: '')); // 行末和弦后无词
  }
  return units;
}

/// 和弦指法表:frets 按 **G C E A**(从左到右四根弦)顺序,0 = 空弦,数字 = 按第几品。
/// 照搬 Web 版 CHORDS。画指法图(ChordDiagram)时按这个数组画按弦点 / 空弦圈。
const Map<String, List<int>> chordShapes = {
  'C': [0, 0, 0, 3],
  'G': [0, 2, 3, 2],
  'Am': [2, 0, 0, 0],
  'F': [2, 0, 1, 0],
};

/// 一行歌词,和弦用 [C] 标在"该弹的那个词"前面(行内和弦)。
/// chords 是从歌词里解析出来的(按出现顺序),给节拍器拍扁成一条线往前推进用。
@immutable
class Line {
  final String lyric; // 带 [和弦] 标记的歌词

  const Line({required this.lyric});

  /// 这一行里的和弦,按出现顺序。
  List<String> get chords =>
      parseInline(lyric).where((t) => t.isChord).map((t) => t.chord!).toList();
}

/// 歌曲里的一个段落,例如"副歌"。name 可空 —— 单段落的歌常没有名字。
@immutable
class Section {
  final String? name;
  final List<Line> lines;

  const Section({this.name, required this.lines});
}

/// 一首可练习的歌。
///
/// - tempo:速度(BPM,每分钟多少拍),决定节拍器快慢
/// - beatsPerChord:一个和弦持续几拍后换下一个
@immutable
class Song {
  final String title;
  final int tempo;
  final int beatsPerChord;
  final List<Section> sections;

  const Song({
    required this.title,
    required this.tempo,
    this.beatsPerChord = 4,
    required this.sections,
  });
}

/// 歌曲库。界面里用顶栏下拉框选一首。
///
/// 原 IZ 版把《Over the Rainbow》和《What a Wonderful World》串成一首串烧(medley),
/// 这里按"两首就该分两条"的原则拆成两首,免得新手以为后半段是《Over the Rainbow》的词。
/// 歌词用行内和弦([C]词),比 Web 版(和弦单独一排)更清楚和弦落在哪个词上。
const List<Song> songs = [
  Song(
    title: '🌈 Somewhere Over the Rainbow',
    tempo: 72,
    beatsPerChord: 4,
    sections: [
      Section(
        lines: [
          Line(lyric: '[C]Somewhere [G]over the [Am]rainbow, [F]way up high'),
          Line(
            lyric:
                '[C]And the [G]dreams that you [Am]dream of, [F]once in a lullaby',
          ),
          Line(lyric: '[C]Somewhere [G]over the [Am]rainbow, [F]bluebirds fly'),
          Line(
            lyric:
                "[C]And the [G]dreams that you [Am]dare to, [F]oh why oh why can't I",
          ),
        ],
      ),
    ],
  ),
  Song(
    title: '🌻 What a Wonderful World',
    tempo: 70,
    beatsPerChord: 4,
    sections: [
      Section(
        lines: [
          Line(lyric: '[C]Well I [G]see trees of [Am]green, [F]red roses too'),
          Line(lyric: '[C]I [G]watch them [Am]bloom for [F]me and you'),
          Line(
            lyric: '[Am]And I [F]think to my[C]self, [G]what a wonderful world',
          ),
        ],
      ),
    ],
  ),
  Song(
    title: '🎹 Let It Be',
    tempo: 70,
    beatsPerChord: 4,
    sections: [
      Section(
        lines: [
          Line(lyric: '[C]When I [G]find myself [Am]in [F]times of trouble'),
          Line(lyric: '[C]Mother [G]Mary [F]comes to [C]me'),
          Line(lyric: '[C]Speaking [G]words of [Am]wisdom, [F]let it be'),
          Line(
            lyric:
                '[C]And in my [G]hour of [F]darkness, she is standing right in front of [C]me',
          ),
        ],
      ),
      Section(
        name: '🎶 副歌',
        lines: [
          Line(
            lyric: '[Am]Let it be, [G]let it be, [F]let it be, [C]let it be',
          ),
          Line(lyric: '[Am]Whisper [G]words of [F]wisdom, [C]let it be'),
        ],
      ),
    ],
  ),
  Song(
    title: '☀️ You Are My Sunshine',
    tempo: 88,
    beatsPerChord: 4,
    sections: [
      Section(
        lines: [
          Line(lyric: '[C]You are my [G]sunshine, my only sunshine'),
          Line(lyric: '[C]You make me happy when [G]skies are gray'),
          Line(lyric: "[C]You'll never know dear, [G]how much I love you"),
          Line(lyric: "[C]Please don't take my [G]sunshine [C]away"),
        ],
      ),
    ],
  ),
];
