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
import 'dart:math';

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
  'D': [2, 2, 2, 0], // 三根手指按第2品(G C E)、A 空弦
  'Em': [0, 4, 3, 2], // G 空弦,C 按第4品、E 第3品、A 第2品(够不着就慢慢练)
};

/// 一拍 = 两个 8 分音符槽位。节奏型就按这些槽位描述,这样"上扫"这种落在后半拍的扫弦才表达得出来。
/// 约定:槽 0 = 第1拍正拍、槽 1 = 第1拍的"&"(后半拍)、槽 2 = 第2拍正拍 …… 一个和弦共 beatsPerChord×2 个槽。
/// 用 beatsPerChord×2 而不是更细的 16 分音符:尤克里里常用节奏型最细到半拍,够用且界面不挤。
/// 一个扫弦的方向:向下扫 / 向上扫 / 这一下不扫(休止,留着看节奏空隙用)。
enum StrumDir { down, up, rest }

/// 节奏型里的一下扫弦:在哪个槽位、往哪个方向扫。
@immutable
class Strum {
  final int slot;
  final StrumDir dir;

  const Strum(this.slot, this.dir);
}

/// 节奏型(Strum Pattern):在一个和弦内的扫弦序列。strums 里没出现的槽位 = 休止。
@immutable
class StrumPattern {
  final String name;
  final List<Strum> strums;

  const StrumPattern({required this.name, required this.strums});

  /// 拍成"按槽位取方向"的数组(长度 = beatsPerChord×2),给界面逐槽高亮用。
  /// 没出现的槽算 rest;越界的扫弦忽略(防节奏型比一小节长)。
  List<StrumDir> grid(int beatsPerChord) {
    final g = List<StrumDir>.filled(beatsPerChord * 2, StrumDir.rest);
    for (final s in strums) {
      if (s.slot >= 0 && s.slot < g.length) g[s.slot] = s.dir;
    }
    return g;
  }
}

/// 给一个和弦持续拍数,返回几个常用节奏型供选。
/// 「全下」:每个正拍一个下扫(最简单,跟节拍器一拍一下一样)——新手起步用它。
/// 「下上」:每个 8 分音符都扫(偶数槽下、奇数槽上)——稳的密集伴奏。
/// 「海岛」(Island/Calypso):D - D U - U D U——尤克里里最招牌的节奏,练熟它能弹一大半流行歌。
/// 「民谣」(Folk):D - D U U - D U——民谣弹唱常用,比海岛多一个正拍下扫、更稳。
/// 「摇滚」:D - D U D U D U——密集连续扫,鼓点感强、推得动。
///   注:海岛/民谣/摇滚都按 4 拍和弦(8 槽)写的;别的拍数会自动截断(grid 会忽略越界槽),不崩但形状会怪。
///   现有歌曲都是 4 拍,所以没问题。
List<StrumPattern> patternsFor(int beatsPerChord) {
  return [
    StrumPattern(
      name: '全下',
      strums: [
        for (var s = 0; s < beatsPerChord * 2; s += 2)
          Strum(s, StrumDir.down),
      ],
    ),
    StrumPattern(
      name: '下上',
      strums: [
        for (var s = 0; s < beatsPerChord * 2; s++)
          Strum(s, s.isEven ? StrumDir.down : StrumDir.up),
      ],
    ),
    const StrumPattern(
      name: '海岛',
      strums: [
        Strum(0, StrumDir.down),
        Strum(2, StrumDir.down),
        Strum(3, StrumDir.up),
        Strum(5, StrumDir.up),
        Strum(6, StrumDir.down),
        Strum(7, StrumDir.up),
      ],
    ),
    const StrumPattern(
      name: '民谣',
      strums: [
        Strum(0, StrumDir.down),
        Strum(2, StrumDir.down),
        Strum(3, StrumDir.up),
        Strum(4, StrumDir.up),
        Strum(6, StrumDir.down),
        Strum(7, StrumDir.up),
      ],
    ),
    const StrumPattern(
      name: '摇滚',
      strums: [
        Strum(0, StrumDir.down),
        Strum(2, StrumDir.down),
        Strum(3, StrumDir.up),
        Strum(4, StrumDir.down),
        Strum(5, StrumDir.up),
        Strum(6, StrumDir.down),
        Strum(7, StrumDir.up),
      ],
    ),
  ];
}

/// 自动提速(渐进提速):每过一遍 +step BPM,封顶 cap 就不再涨。
/// 本应用里 cap = 歌的原速——_tempo 练到原速就停,符合"从慢练到原速"的练法;
/// 已经等于/超过 cap(手动加过速)的不再往上加。
/// 纯函数、无副作用:单独抽出来是为了能在无头测试里直接锁它的边界行为,不依赖 Timer / setState。
int nextRampTempo(int current, int cap, {int step = 3}) =>
    current < cap ? min(current + step, cap) : current;

/// 秒数 → "Xs" / "Xm" / "XhYm",给"练了多久"显示用。
/// <60s 显示秒,够 1 分钟显示分,够 1 小时显示"时分"(如 1h12m)。
/// 抽成纯函数放这:SongScreen 顶栏和统计页都要格式化时长,共用一份;也能在无头测试里直接锁它。
String formatPracticeSec(int sec) {
  if (sec < 60) return '${sec}s';
  final m = sec ~/ 60;
  if (m < 60) return '${m}m';
  final h = m ~/ 60;
  return '${h}h${m % 60}m';
}

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
  Song(
    title: '🌴 Riptide',
    tempo: 102,
    beatsPerChord: 4,
    sections: [
      Section(
        lines: [
          Line(lyric: "[Am]I was scared of [G]dentists and the [C]dark"),
          Line(
            lyric: "[Am]I was scared of [G]pretty girls and [C]starting conversations",
          ),
          Line(lyric: "[Am]Oh, all my [G]friends are turning [C]green"),
          Line(
            lyric: "[Am]You're the ma[G]gician's assistant [C]in their dream",
          ),
        ],
      ),
      Section(
        name: '🎶 副歌',
        lines: [
          Line(lyric: "[Am]Lady, running [G]down to the [C]riptide"),
          Line(lyric: "[Am]Taken away [G]to the dark [C]side"),
          Line(lyric: "[Am]I wanna be your [G]left hand [C]man"),
        ],
      ),
    ],
  ),
  Song(
    title: "😎 I'm Yours",
    tempo: 88,
    beatsPerChord: 4,
    sections: [
      Section(
        lines: [
          Line(
            lyric: "[G]Well you [D]done done me and you [Em]bet I felt it [C]",
          ),
          Line(
            lyric: "[G]I tried to be [D]chill but you're so [Em]hot that I melted [C]",
          ),
          Line(
            lyric: "[G]Listen to the [D]music of the [Em]moment people [C]dance and sing",
          ),
        ],
      ),
      Section(
        name: '🎶 副歌',
        lines: [
          Line(
            lyric: "[G]But I won't [D]hesitate no [Em]more, no more [C]",
          ),
          Line(lyric: "[G]It cannot [D]wait, I'm [Em]yours [C]"),
        ],
      ),
    ],
  ),
  Song(
    title: '🌙 Stand By Me',
    tempo: 118,
    beatsPerChord: 4,
    sections: [
      Section(
        lines: [
          Line(
            lyric: "[C]When the [Am]night has [F]come and the [G]land is dark",
          ),
          Line(
            lyric: "[C]And the [Am]moon is the [F]only light we'll [G]see",
          ),
          Line(
            lyric: "[C]No I [Am]won't be a-[F]fraid, no I [G]won't shed a tear",
          ),
        ],
      ),
      Section(
        name: '🎶 副歌',
        lines: [
          Line(lyric: "[C]So darlin', [Am]darlin' [F]stand, by [G]me"),
          Line(
            lyric: "[C]Oh [Am]stand, [F]by me, oh [G]stand, stand by me",
          ),
        ],
      ),
    ],
  ),
  Song(
    title: '🚂 Hey Soul Sister',
    tempo: 104,
    beatsPerChord: 4,
    sections: [
      Section(
        lines: [
          Line(
            lyric:
                '[C]Your lipstick stains, on the [G]front lobe of my left side [Am]brains [F]',
          ),
          Line(
            lyric:
                "[C]I knew I wouldn't [G]forget you, and so I went and [Am]let you blow my [F]mind",
          ),
          Line(
            lyric:
                '[C]Your sweet moon beam, the [G]smell of you in every [Am]single dream I [F]dream',
          ),
        ],
      ),
      Section(
        name: '🎶 副歌',
        lines: [
          Line(
            lyric:
                "[C]He-e-ey, soul sister, [G]ain't that Mr. Mister [Am]on the radio, [F]stereo",
          ),
          Line(
            lyric:
                "[C]He-e-ey, soul sister, [G]I don't wanna miss a [Am]single thing you [F]do, [C]tonight",
          ),
        ],
      ),
    ],
  ),
  Song(
    title: '🧟 Zombie',
    tempo: 82,
    beatsPerChord: 4,
    sections: [
      Section(
        lines: [
          Line(
            lyric:
                '[Em]Another head hangs [C]lowly, child is [G]slowly taken [D]',
          ),
          Line(
            lyric:
                '[Em]And the violence [C]caused such silence, who are [G]we mistaken [D]',
          ),
        ],
      ),
      Section(
        name: '🎶 副歌',
        lines: [
          Line(
            lyric:
                '[Em]In your head, in your [C]head, [G]zombie, [D]zombie',
          ),
          Line(
            lyric:
                "[Em]What's in your head, in your [C]head, [G]zombie, [D]zombie",
          ),
        ],
      ),
    ],
  ),
  Song(
    title: '🌅 Counting Stars',
    tempo: 122,
    beatsPerChord: 4,
    sections: [
      Section(
        lines: [
          Line(
            lyric:
                '[Am]I see this life, like a [C]swinging vine, swing my [G]heart across the [F]line',
          ),
          Line(
            lyric:
                '[Am]In my face is flashing signs, [C]seek it out and ye shall [G]find [F]',
          ),
        ],
      ),
      Section(
        name: '🎶 副歌',
        lines: [
          Line(
            lyric:
                "[Am]Lately I've been, I've been [C]losing sleep, [G]dreaming about the things that we [F]could be",
          ),
          Line(
            lyric:
                "[Am]Baby I've been, I've been [C]praying hard, said no more [G]counting dollars, we'll be [F]counting stars",
          ),
        ],
      ),
    ],
  ),
];
