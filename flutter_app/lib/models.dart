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

/// 练习日历用的"日期键":把 DateTime 折成 date-only(零点)再取 ISO 字符串前 10 位
/// → 'yyyy-MM-dd'(零填充,如 '2026-08-06')。toIso8601String 已自带零填充,取前 10 位刚好。
/// 当存"哪天练过"的字典 key / 列表项用。抽成纯函数:存(SongScreen)、读(统计页)、测都要,共用一份。
String practiceDayKey(DateTime d) =>
    DateTime(d.year, d.month, d.day).toIso8601String().substring(0, 10);

/// 连续打卡天数(练习日历的"🔥 连续 N 天"):从 today 往回数连续命中的天数。
/// [practicedDays] = practiceDayKey 字符串列表(哪天练过);[today] 任意时刻都行(内部折成零点)。
/// 规则:今天练了→从今天起数;今天没练但昨天练了→从昨天起数(今天还没结束, streak 仍算到昨天为止,
///      今天再练就续上);今天昨天都没练→0。
/// 纯函数、无副作用:抽出来是为了在无头测试里直接锁它(连练 / 断了 / 今天还没练这几种边界),
/// 不依赖系统时钟(DateTime.now)——today 由调用方传,测试传固定值。
int currentStreak(List<String> practicedDays, DateTime today) {
  final set = practicedDays.toSet();
  final todayDate = DateTime(today.year, today.month, today.day);
  // 起点:今天命中→今天;否则昨天命中→昨天(今天还没练, streak 算到昨天为止);否则 0。
  DateTime cursor;
  if (set.contains(practiceDayKey(todayDate))) {
    cursor = todayDate;
  } else if (set.contains(practiceDayKey(todayDate.subtract(const Duration(days: 1))))) {
    cursor = todayDate.subtract(const Duration(days: 1));
  } else {
    return 0;
  }
  var n = 0;
  while (set.contains(practiceDayKey(cursor))) {
    n++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return n;
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
/// - id:稳定标识。偏好(速度 / AB / 遍数 / 秒数)按它存,不按下标——这样加 / 删用户歌
///   不会让下标挪位、把"这首歌练了多少"串到别的歌上。内置歌的 id = 它在下标里的位置
///   (字符串 '0'、'1'……),跟旧版"按下标存"的偏好键一模一样 → 旧数据零迁移、原样读得到。
/// - tempo:速度(BPM,每分钟多少拍),决定节拍器快慢
/// - beatsPerChord:一个和弦持续几拍后换下一个
@immutable
class Song {
  final String id;
  final String title;
  final int tempo;
  final int beatsPerChord;
  final List<Section> sections;

  const Song({
    this.id = '',
    required this.title,
    required this.tempo,
    this.beatsPerChord = 4,
    required this.sections,
  });

  /// 复制本歌、只改 id(给内置歌在加载时补稳定 id 用;其余字段原样)。
  Song copyWith({String? id}) => Song(
        id: id ?? this.id,
        title: title,
        tempo: tempo,
        beatsPerChord: beatsPerChord,
        sections: sections,
      );
}

/// 内置歌曲(原始、不带 id)。加载时由下面【songs】那条给每首补上稳定 id = 它的下标,
/// 再(第43b步起)追加用户自加的歌。界面读的是下面那条 songs,不是这份原始的。
///
/// 原 IZ 版把《Over the Rainbow》和《What a Wonderful World》串成一首串烧(medley),
/// 这里按"两首就该分两条"的原则拆成两首,免得新手以为后半段是《Over the Rainbow》的词。
/// 歌词用行内和弦([C]词),比 Web 版(和弦单独一排)更清楚和弦落在哪个词上。
const List<Song> builtinSongs = [
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
  // —— 第42步新加的几首(行内和弦;都只用 chordShapes 里那 6 个:C G Am F D Em,和弦图画得出)——
  Song(
    title: "💕 Can't Help Falling in Love",
    tempo: 66, // 慢抒情,新手跟得上
    beatsPerChord: 4,
    sections: [
      Section(
        lines: [
          Line(lyric: "[C]Wise men [Em]say, [Am]only fools [F]rush in"),
          Line(lyric: "[C]But I [Em]can't help [Am]falling in [F]love with you"),
          Line(lyric: "[C]Shall I [Em]stay, [Am]would it [F]be a sin"),
          Line(lyric: "[C]If I [Em]can't help [Am]falling in [F]love with you"),
        ],
      ),
      Section(
        name: '🎶 副歌',
        lines: [
          Line(lyric: "[F]Like a [G]river [Am]flows, [C]surely to the sea"),
          Line(lyric: "[F]Darling [G]so it [Am]goes, [C]some things are meant to be"),
          Line(lyric: "[C]Take my [Em]hand, [Am]take my [F]whole life too"),
          Line(lyric: "[C]For I [Em]can't help [Am]falling in [F]love with you"),
        ],
      ),
    ],
  ),
  Song(
    title: '🤝 Lean on Me',
    tempo: 82,
    beatsPerChord: 4,
    sections: [
      Section(
        lines: [
          Line(lyric: "[C]Sometimes in our [G]lives we [Am]all have pain and [F]sorrow"),
          Line(lyric: "[C]But if we are [G]wise we [Am]know there's always [F]tomorrow"),
        ],
      ),
      Section(
        name: '🎶 副歌',
        lines: [
          Line(lyric: "[C]Lean on [G]me, when you're [Am]not [F]strong"),
          Line(lyric: "[F]And I'll be your [C]friend, I'll help you [G]carry on"),
          Line(lyric: "[C]For it won't be [G]long, till I'm [Am]gonna need somebody to [F]lean on"),
        ],
      ),
    ],
  ),
  Song(
    title: "🍃 Blowin' in the Wind",
    tempo: 84,
    beatsPerChord: 4,
    sections: [
      Section(
        lines: [
          Line(lyric: "[G]How many [C]roads must a [G]man walk down"),
          Line(lyric: "[G]Before you [C]call him a [G]man"),
          Line(lyric: "[Em]How many [C]seas must a [G]white dove sail"),
          Line(lyric: "[Em]Before she [C]sleeps in the [D]sand"),
        ],
      ),
      Section(
        name: '🎶 答案',
        lines: [
          Line(lyric: "[G]The answer my [C]friend is [G]blowin' in the wind"),
          Line(lyric: "[G]The answer is [C]blowin' in the [D]wind"),
        ],
      ),
    ],
  ),
];

/// 【第43a步】内置歌补上稳定 id(= 各自下标)后的歌曲库。界面读这份。
///
/// id 取下标的字符串:'0'、'1'…… 跟旧版"按下标存"的偏好键(pref_tempo_0 等)完全一致 →
/// 旧练习数据零迁移、原样读得到。第43b步起歌库(SongStore)会在这后面追加用户自加的歌
/// (用 'u1'、'u2' 这种 id,不跟内置的数字 id 撞);在那之前界面读的就是这 13 首内置歌。
final List<Song> songs = [
  for (var i = 0; i < builtinSongs.length; i++) builtinSongs[i].copyWith(id: '$i'),
];
