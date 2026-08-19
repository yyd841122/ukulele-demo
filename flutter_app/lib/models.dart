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
/// 画指法图(ChordDiagram)时按这个数组画按弦点 / 空弦圈。
///
/// 第52步从 6 个扩到 20 个;第53步再扩到 43 个,新增大七/小七/sus4/sus2/dim/aug/E。
/// 按"三和弦→七和弦→挂留→减增"分组排,方便和弦速查页浏览。
const Map<String, List<int>> chordShapes = {
  // —— 大三和弦(Major) ——
  'C': [0, 0, 0, 3],
  'D': [2, 2, 2, 0],
  'F': [2, 0, 1, 0],
  'G': [0, 2, 3, 2],
  'A': [2, 1, 0, 0],
  'Bb': [3, 2, 1, 1],
  'E': [4, 4, 4, 2],

  // —— 小三和弦(Minor) ——
  'Am': [2, 0, 0, 0],
  'Bm': [4, 2, 2, 2],
  'Cm': [0, 3, 3, 3],
  'Dm': [2, 2, 1, 0],
  'Em': [0, 4, 3, 2],
  'Fm': [1, 0, 1, 3],
  'Gm': [0, 2, 3, 1],

  // —— 属七和弦(Dominant 7th) ——
  'A7': [0, 1, 0, 0],
  'B7': [2, 3, 2, 2],
  'C7': [0, 0, 0, 1],
  'D7': [2, 2, 2, 3],
  'E7': [1, 2, 0, 2],
  'G7': [0, 2, 1, 2],

  // —— 大七和弦(Major 7th) ——
  'Cmaj7': [0, 0, 0, 2],
  'Fmaj7': [2, 4, 1, 0],
  'Gmaj7': [0, 2, 2, 2],
  'Amaj7': [1, 1, 0, 0],

  // —— 小七和弦(Minor 7th) ——
  'Dm7': [2, 2, 1, 3],
  'Am7': [0, 0, 0, 0],
  'Em7': [0, 2, 0, 2],
  'Bm7': [2, 2, 2, 2],
  'Cm7': [3, 3, 3, 3],
  'Fm7': [1, 3, 1, 3],
  'Gm7': [0, 2, 1, 1],

  // —— 挂四和弦(sus4) ——
  'Csus4': [0, 0, 1, 3],
  'Dsus4': [0, 2, 3, 0],
  'Fsus4': [3, 0, 1, 1],
  'Gsus4': [0, 2, 3, 3],
  'Asus4': [2, 2, 0, 0],

  // —— 挂二和弦(sus2) ——
  'Csus2': [0, 2, 0, 3],
  'Dsus2': [2, 2, 0, 0],
  'Gsus2': [0, 2, 3, 0],

  // —— 减和弦(dim) ——
  'Bdim': [4, 2, 1, 2],
  'Ddim': [1, 2, 1, 0],

  // —— 增和弦(aug) ——
  'Caug': [1, 0, 0, 3],
  'Gaug': [0, 3, 3, 2],
};

/// 一个和弦分类(给和弦速查页数据驱动分组用,替掉原来按和弦名 contains/endsWith 的脆弱推断:
/// 像 C#m / Bbmaj7 这种命名一变就会被错归类)。name 是中文显示标签,chords 是该类下的和弦名,
/// 顺序就是浏览顺序。每个和弦名都必须在 chordShapes 里有指法(点卡要画图 + 试听)。
class ChordCategory {
  final String name;
  final List<String> chords;
  const ChordCategory(this.name, this.chords);
}

/// 和弦速查页的分类(顺序 = 三和弦 → 七和弦 → 挂留 → 减增),和 chordShapes 的注释分组一致。
/// 改 / 加和弦时:chordShapes 加指法,这里把名字塞进对应分类。
const List<ChordCategory> chordCategories = [
  ChordCategory('大三', ['C', 'D', 'F', 'G', 'A', 'Bb', 'E']),
  ChordCategory('小三', ['Am', 'Bm', 'Cm', 'Dm', 'Em', 'Fm', 'Gm']),
  ChordCategory('属七', ['A7', 'B7', 'C7', 'D7', 'E7', 'G7']),
  ChordCategory('大七', ['Cmaj7', 'Fmaj7', 'Gmaj7', 'Amaj7']),
  ChordCategory('小七', ['Dm7', 'Am7', 'Em7', 'Bm7', 'Cm7', 'Fm7', 'Gm7']),
  ChordCategory('sus4', ['Csus4', 'Dsus4', 'Fsus4', 'Gsus4', 'Asus4']),
  ChordCategory('sus2', ['Csus2', 'Dsus2', 'Gsus2']),
  ChordCategory('dim', ['Bdim', 'Ddim']),
  ChordCategory('aug', ['Caug', 'Gaug']),
];

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
/// 「慢扫」:只第 1、3 拍下扫(槽 0、4),一拍一下很疏——抒情慢歌最有呼吸,比「全下」还空。
/// 「海岛」(Island/Calypso):D - D U - U D U——尤克里里最招牌的节奏,练熟它能弹一大半流行歌。
/// 「民谣」(Folk):D - D U U - D U——民谣弹唱常用,比海岛多一个正拍下扫、更稳。
/// 「下下上」:D D U - D D U - 重复两组——民谣摇滚弹唱经典推进,开头双下很有冲劲(比「下上」多了 16 分感)。
/// 「摇滚」:D - D U D U D U——密集连续扫,鼓点感强、推得动。
/// 「雷鬼切分」:D - - U D - - U——反拍(后半拍)上扫重,雷鬼 / 流行切分感,比海岛更跳、更"躺"。
///   全下 / 下上 / 慢扫 按拍数【动态生成】,任何拍数都正常。
///   其余按 4 拍(8 槽)写死(第51步起):非 4 拍歌(如 3 拍华尔兹)不返回它们——
///   否则 grid 会截断、形状怪;而且这些本就是 4/4 招牌节奏,硬塞别的拍数也不合乐理。非 4 拍只给前三个。
List<StrumPattern> patternsFor(int beatsPerChord) {
  final out = <StrumPattern>[
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
    StrumPattern(
      // 慢扫:正拍里只第 1、3 拍(每两拍一下)。偶数槽里再隔一个取:slot 0,4,8…
      // 即「步长 4」。beatsPerChord 不限 4——6/8 拍歌给 0/4(三下)、8 拍给 0/4/8(四下)都自然。
      name: '慢扫',
      strums: [
        for (var s = 0; s < beatsPerChord * 2; s += 4)
          Strum(s, StrumDir.down),
      ],
    ),
  ];
  // 4 拍才给招牌节奏(它们按 8 槽写死,别的拍数会截断 / 不合乐理)。
  if (beatsPerChord == 4) {
    out.addAll(const [
      StrumPattern(
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
      StrumPattern(
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
      StrumPattern(
        // 下下上:开头双下(槽 0 正拍 + 槽 1 后半拍)是连续 16 分感的双下,民谣摇滚推进。
        // 后半小节(槽 4-6)重复一遍对称。槽 2、6 后半及槽 3、7 空是它的切分味道来源。
        name: '下下上',
        strums: [
          Strum(0, StrumDir.down),
          Strum(1, StrumDir.down),
          Strum(2, StrumDir.up),
          Strum(4, StrumDir.down),
          Strum(5, StrumDir.down),
          Strum(6, StrumDir.up),
        ],
      ),
      StrumPattern(
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
      StrumPattern(
        // 雷鬼切分:正拍下扫 + 反拍(后半拍)上扫,中段全空。正拍稳、反拍跳,雷鬼/流行的"躺"感。
        name: '雷鬼切分',
        strums: [
          Strum(0, StrumDir.down),
          Strum(3, StrumDir.up),
          Strum(4, StrumDir.down),
          Strum(7, StrumDir.up),
        ],
      ),
    ]);
  }
  return out;
}

/// 自动提速(渐进提速):每过一遍 +step BPM,封顶 cap 就不再涨。
/// 本应用里 cap = 歌的原速——_tempo 练到原速就停,符合"从慢练到原速"的练法;
/// 已经等于/超过 cap(手动加过速)的不再往上加。
/// 纯函数、无副作用:单独抽出来是为了能在无头测试里直接锁它的边界行为,不依赖 Timer / setState。
int nextRampTempo(int current, int cap, {int step = 3}) =>
    current < cap ? min(current + step, cap) : current;

/// i 是长度 length(>1)序列的最后一个下标吗——即"再走一步就绕回开头"。
/// 给【循环过渡拍】用:琶音(_chordIdx)/指弹(_globalSlot)回跳时,只在整轮走完
/// (最后一个 → 回第1个)才插过渡拍,不是每个元素都插;length<=1 不绕环,不插。
/// 抽成纯函数:两屏共用同一判断 + 无头测试锁住边界(末位/非末位/单元素/空),跟 nextRampTempo 一个套路。
bool isLastIndex(int i, int length) => length > 1 && i == length - 1;

/// 移调(虚拟变调夹)在练习页信息行里的显示片段:
/// 0 → 空串(不移调就不显示);否则形如「移调 +2半音 · 」,直接拼在信息行最前面。
/// 抽成纯函数:跟 formatPracticeSec 一个套路,锁住正 / 负 / 零三种显示,无头可测。
String formatTranspose(int semis) {
  if (semis == 0) return '';
  final sign = semis > 0 ? '+' : '';
  return '移调 $sign$semis半音 · ';
}

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

  /// 序列化成 JSON(给用户自加的歌持久化用;内置歌不存——它们在代码里)。
  /// id 也存:跨 app 重启读回来时 id 不变 → 这首歌的练习记录(按 id 存)才接得上、不丢。
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'tempo': tempo,
        'beatsPerChord': beatsPerChord,
        'sections': [
          for (final s in sections)
            {
              if (s.name != null) 'name': s.name,
              'lines': [for (final l in s.lines) {'lyric': l.lyric}],
            },
        ],
      };

  /// 从 JSON 还原成 Song(用户歌启动时读出来)。字段缺失给默认值,防旧版存的歌缺新字段挂掉。
  factory Song.fromJson(Map<String, dynamic> j) => Song(
        id: j['id'] as String? ?? '',
        title: j['title'] as String? ?? '(未命名)',
        tempo: (j['tempo'] as num?)?.toInt() ?? 80,
        beatsPerChord: (j['beatsPerChord'] as num?)?.toInt() ?? 4,
        sections: [
          for (final s in (j['sections'] as List?) ?? const [])
            _sectionFromJson(s as Map<String, dynamic>),
        ],
      );
}

/// 这首歌用了哪些和弦(从歌词里 [C] 标记提取、去重,只认 chordShapes 里有的合法和弦)。
/// 给难度标签用。纯函数、无头可测。
Set<String> chordsOf(Song s) {
  final chords = <String>{};
  for (final sec in s.sections) {
    for (final line in sec.lines) {
      for (final m in RegExp(r'\[([^\]]+)\]').allMatches(line.lyric)) {
        final name = m.group(1)!;
        if (chordShapes.containsKey(name)) chords.add(name);
      }
    }
  }
  return chords;
}

/// 歌曲难度(给新手标"从哪首入手"):从用的和弦【算】出来、不写死,和弦改了难度自动跟上;
/// 用户自加的歌也自动有难度标签。规则(按当前曲库全是开放把位入门和弦标定):
///   1 入门:≤3 个和弦、且没碰 F / 7 和弦(C/G/Am/D/Em/A/Dm 这类最基础的)。F 是新手第一道坎。
///   3 进阶:5 个以上和弦(切换多)。
///   2 初级:其余(3-4 个和弦,常含 F 或 7 和弦)。
/// 纯函数、无头可测。
int difficultyOf(Song s) {
  final c = chordsOf(s);
  if (c.isEmpty) return 2; // 没和弦标记(理论不会)→ 中性
  final hasF = c.contains('F'); // F:新手第一道坎
  final hasSeventh = c.any((x) => x.contains('7')); // 7 和弦要加指
  if (!hasF && !hasSeventh && c.length <= 3) return 1;
  if (c.length >= 5) return 3;
  return 2;
}

/// 难度 → 中文标签(界面显示用)。
String difficultyLabel(int d) =>
    const {1: '入门', 2: '初级', 3: '进阶'}[d] ?? '初级';

/// 一段的反序列化(Song.fromJson 用,抽出来免得集合 for 里塞语句)。
Section _sectionFromJson(Map<String, dynamic> j) => Section(
      name: j['name'] as String?,
      lines: [
        for (final l in (j['lines'] as List?) ?? const [])
          Line(lyric: (l as Map<String, dynamic>)['lyric'] as String? ?? ''),
      ],
    );

/// 把"加歌表单"里那框歌词文本拍成段落(第46步起支持 #名字 段落命名)。规则:
///  - 空行 = 分段(匿名段);
///  - 行首 `#名字` = 给【接下来的】段落起名(如 `#副歌`),这行本身不是歌词;
///  - 其余非空行 = 一条 Line(行内 [和弦] 由 Line.chords 自己解析)。
/// 名字后没歌词的空段会被丢掉(不造没词的段);`#` 后面空白当匿名段(不造空名字)。
/// 纯函数、无副作用:抽出来能在无头测试里直接锁解析(有名 / 无名 / 混合 / 名字后没词 / 空 #)。
List<Section> parseLyrics(String text) {
  final sections = <Section>[];
  var current = <Line>[];
  String? pendingName; // 下一段的名字(由 #名字 行设定);null = 匿名段
  void flush() {
    if (current.isNotEmpty) {
      sections.add(Section(name: pendingName, lines: current));
      current = <Line>[];
    }
    pendingName = null;
  }

  for (final raw in text.split('\n')) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      flush(); // 空行 = 分段
    } else if (trimmed.startsWith('#')) {
      flush(); // 先收尾当前段,再用这行给下一段命名
      // 名字 = '#' 后面的文字,但剥掉行内 [和弦](第51步:修 #副歌 [C] → 名字别把 [C] 也吃进去。
      // # 行本身不是歌词,上面的 [和弦] 没有词可挂,只能丢弃;留它会让段名变成「副歌 [C]」很怪)。
      final rawName = trimmed.substring(1).replaceAll(RegExp(r'\[[^\]]*\]'), '').trim();
      pendingName = rawName.isEmpty ? null : rawName; // 剥完空白 → 匿名(不造空名字)
    } else {
      current.add(Line(lyric: raw));
    }
  }
  flush();
  return sections;
}

/// 内置歌曲(原始、不带 id)。加载时由下面【songs】那条给每首补上稳定 id = 它的下标,
/// 再(第43b步起)追加用户自加的歌。界面读的是下面那条 songs,不是这份原始的。
///
/// 歌词用行内和弦([C]词),比 Web 版(和弦单独一排)更清楚和弦落在哪个词上。
///
/// 全部为公有领域(PD)曲目:词曲作者均去世逾版权保护期,可自由使用;和弦套路由本 app 配。
const List<Song> builtinSongs = [
  // 这些歌的词、曲作者均已去世逾版权保护期(作者去世+50年,中国/多数国家),进入公有领域,
  // 可自由使用。和弦套路由本 app 配(非原曲精确和声),新手友好、贴合歌曲情绪即可。
  // 扫弦歌只给"词+和弦",app 播和弦、用户自己唱旋律——不存在"写错旋律"风险。

  // 送别 —— 李叔同 1915 年填词(曲借用美国 Ordway《Dreaming of Home and Mother》,均 PD)。
  // 华语圈最熟的一首,C 调,4/4,抒情慢歌。和弦走华语抒情套路(C-G-Am-Em 主流动,F-Dm-G 推动收束)。
  // 原作就是四句一段反复吟唱,只录最经典、人人会背的这一段,不臆造段落。
  Song(
    title: "🌅 送别",
    tempo: 72,
    beatsPerChord: 4,
    sections: [
      Section(
        lines: [
          Line(lyric: "[C]长亭外 [G]古道边 [Am]芳草碧连[Em]天"),
          Line(lyric: "[F]晚风拂 [C]柳笛声残 [Dm]夕阳山外[G]山"),
          Line(lyric: "[C]天之涯 [G]地之角 [Am]知交半零[Em]落"),
          Line(lyric: "[F]一瓢浊 [C]酒尽余欢 [Dm]今宵别梦[G]寒"),
        ],
      ),
    ],
  ),

  // Amazing Grace(奇异恩典)—— 18 世纪英国 Newton 作词(PD),全球最熟赞美诗。
  // G 调,3/4 拍(华尔兹),舒缓庄严。和弦用赞美诗最经典的 I-IV-V(G-C-D7)。
  Song(
    title: "✨ 奇异恩典 (Amazing Grace)",
    tempo: 80,
    beatsPerChord: 3,
    sections: [
      Section(
        lines: [
          Line(lyric: "[G]Amazing grace how [G7]sweet the sound"),
          Line(lyric: "[C]That saved a wretch like [G]me"),
          Line(lyric: "[Em]I once was lost but [C]now am found"),
          Line(lyric: "[D7]Was blind but now I [G]see"),
        ],
      ),
    ],
  ),

  // Auld Lang Syne(友谊地久天长)—— 18 世纪苏格兰 Burns 整理(PD),跨年必唱。
  // G 调,4/4。和弦走经典 1-5-6-4(G-D-Em-C),副歌 D 推回 G。
  Song(
    title: "🥂 友谊地久天长 (Auld Lang Syne)",
    tempo: 90,
    beatsPerChord: 4,
    sections: [
      Section(
        name: '主歌',
        lines: [
          Line(lyric: "[G]Should auld acquaintance [D]be forgot"),
          Line(lyric: "[Em]and never brought to [C]mind"),
          Line(lyric: "[G]Should auld acquaintance [D]be forgot"),
          Line(lyric: "[G]and days of auld lang [D]syne"),
        ],
      ),
      Section(
        name: '🎶 副歌',
        lines: [
          Line(lyric: "[G]For auld lang syne my [D]dear"),
          Line(lyric: "[Em]for auld lang [C]syne"),
          Line(lyric: "[G]We'll take a cup o' [D]kindness yet"),
          Line(lyric: "[G]for auld lang [D]syne"),
        ],
      ),
    ],
  ),

  // 茉莉花 —— 中国传统民歌(anonymous,PD),江南小调,五声调式,海外最熟的中国旋律之一。
  // C 调,4/4。和弦走 C-Am-Dm-G 民歌色彩套(C 主、Am 小调色彩、Dm-G 推动循环)。
  Song(
    title: "🌼 茉莉花",
    tempo: 76,
    beatsPerChord: 4,
    sections: [
      Section(
        name: '主歌',
        lines: [
          Line(lyric: "[C]好一朵美丽的 [Am]茉莉花"),
          Line(lyric: "[C]好一朵美丽的 [Am]茉莉花"),
          Line(lyric: "[Dm]芬芳美丽满 [G]枝桠"),
          Line(lyric: "[C]又香又白 [Am]人人夸"),
        ],
      ),
      Section(
        name: '🎶 副歌',
        lines: [
          Line(lyric: "[Dm]让我来将你 [G]摘下"),
          Line(lyric: "[C]送给别人 [Am]家"),
          Line(lyric: "[Dm]茉莉花呀 [G]茉莉花"),
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

// —— 指弹曲谱(第72步) ——
// 跟 Song(和弦进行+歌词)不同:指弹曲谱是按小节组织的精确 TAB 数据,
// 每小节 N 个时值槽(16分音符粒度),每槽定义哪根弦第几品 + 时值。
// 支持真实指弹曲(如卡农/天空之城),不是自动生成的练习型。

/// 指弹曲谱:一首完整的指弹曲子。
@immutable
class FingerpickSong {
  final String title;        // 曲名
  final String subtitle;     // 副标题(作曲/改编,可选)
  final int tempo;           // 建议 BPM
  final int beatsPerBar;     // 每小节几拍(4=4/4 拍)
  final List<FingerpickBar> bars; // 小节列表

  const FingerpickSong({
    required this.title,
    this.subtitle = '',
    required this.tempo,
    this.beatsPerBar = 4,
    required this.bars,
  });

  /// 总槽位数(拍扁一整首曲子的所有16分音符槽)。
  int get totalSlots => bars.fold(0, (sum, b) => sum + b.slots.length);

  /// 把整首曲子的所有槽拍扁成一条线(播放用)。
  List<FingerpickSlot> get flatSlots {
    final out = <FingerpickSlot>[];
    for (final b in bars) { out.addAll(b.slots); }
    return out;
  }
}

/// 指弹谱的一个小节。
@immutable
class FingerpickBar {
  /// 本小节的时值槽列表。每拍4个16分槽、4/4拍一个小节16槽。
  /// 但实际可能少于16(小节不规则/末尾不完整);duration 决定实际时值。
  final List<FingerpickSlot> slots;

  /// 跟这小节对应的歌词/和弦提示(可空)。播放到这小节时下面的歌词区显示它。
  final String? lyric;

  const FingerpickBar({required this.slots, this.lyric});
}

/// 指弹谱的一个时值槽:哪根弦、第几品、多长时值。
@immutable
class FingerpickSlot {
  /// 弦下标:0=G, 1=C, 2=E, 3=A。null=休止(占时值但不弹)。
  final int? stringIndex;

  /// 品位(0=空弦)。stringIndex 为 null 时无意义。
  final int fret;

  /// 时值:1=16分音符, 2=8分, 3=附点8分, 4=4分, 6=附点4分, 8=2分。
  /// 播放时按此决定该槽占多少个16分槽的时间。
  final int duration;

  const FingerpickSlot({this.stringIndex, this.fret = 0, this.duration = 1});

  /// 这个槽该发声吗(stringIndex 非 null 且 duration > 0)。
  bool get shouldPlay => stringIndex != null && duration > 0;

  /// 休止槽(占时值、不弹)。
  const FingerpickSlot.rest({this.duration = 1})
      : stringIndex = null, fret = 0;
}

// 便捷:创建一个指弹槽。s=弦(0-3),f=品,t=时值(1=16分,2=8分,4=4分)。
FingerpickSlot fp(int s, int f, {int t = 1}) => FingerpickSlot(stringIndex: s, fret: f, duration: t);
// 休止槽。
FingerpickSlot fpr({int t = 1}) => FingerpickSlot.rest(duration: t);

// —— 内置指弹曲谱(第73步) ——
// 3 首经典尤克里里指弹曲。每首 = FingerpickSong,按小节组织、每小节含时值槽+歌词提示。
// 弦下标:0=G,1=C,2=E,3=A。时值:1=16分,2=8分,4=4分。空弦=0。

final builtinFingerpickSongs = <FingerpickSong>[
  // ═══ 入门儿歌(第79步):从简到难,旋律简单、适合指弹跟练 ═══
  // C 调唱名指法(全儿歌通用):do=C弦空(1,0) re=C弦2品(1,2) mi=E弦空(2,0)
  //                        fa=E弦1品(2,1) sol=G弦空(0,0) la=A弦空(3,0)。
  // 每小节 4 拍 = 16 个 16 分 tick;四分音符 duration=4,二分音符 duration=8。

  // ═══ 1. 小星星 (Twinkle Twinkle Little Star) ═══
  // 旋律:CC GG | AA G- | FF EE | DD C- | GG FF | EE D- | GG FF | EE D- | CC GG | AA G- | FF EE | DD C-
  FingerpickSong(
    title: '小星星 (Twinkle Twinkle Little Star)',
    subtitle: 'C 调 · 指弹入门',
    tempo: 85,
    bars: [
      FingerpickBar(lyric: '一闪一闪', slots: [ // C C G G
        fp(1,0,t:4), fp(1,0,t:4), fp(0,0,t:4), fp(0,0,t:4),
      ]),
      FingerpickBar(lyric: '亮晶晶', slots: [ // A A G-(二分)
        fp(3,0,t:4), fp(3,0,t:4), fp(0,0,t:8),
      ]),
      FingerpickBar(lyric: '满天都是', slots: [ // F F E E
        fp(2,1,t:4), fp(2,1,t:4), fp(2,0,t:4), fp(2,0,t:4),
      ]),
      FingerpickBar(lyric: '小星星', slots: [ // D D C-(二分)
        fp(1,2,t:4), fp(1,2,t:4), fp(1,0,t:8),
      ]),
      FingerpickBar(lyric: '挂在天上', slots: [ // G G F F
        fp(0,0,t:4), fp(0,0,t:4), fp(2,1,t:4), fp(2,1,t:4),
      ]),
      FingerpickBar(lyric: '放光明', slots: [ // E E D-(二分)
        fp(2,0,t:4), fp(2,0,t:4), fp(1,2,t:8),
      ]),
      FingerpickBar(lyric: '好像许多', slots: [ // G G F F
        fp(0,0,t:4), fp(0,0,t:4), fp(2,1,t:4), fp(2,1,t:4),
      ]),
      FingerpickBar(lyric: '小眼睛', slots: [ // E E D-(二分)
        fp(2,0,t:4), fp(2,0,t:4), fp(1,2,t:8),
      ]),
      FingerpickBar(lyric: '一闪一闪', slots: [ // C C G G
        fp(1,0,t:4), fp(1,0,t:4), fp(0,0,t:4), fp(0,0,t:4),
      ]),
      FingerpickBar(lyric: '亮晶晶', slots: [ // A A G-(二分)
        fp(3,0,t:4), fp(3,0,t:4), fp(0,0,t:8),
      ]),
      FingerpickBar(lyric: '满天都是', slots: [ // F F E E
        fp(2,1,t:4), fp(2,1,t:4), fp(2,0,t:4), fp(2,0,t:4),
      ]),
      FingerpickBar(lyric: '小星星', slots: [ // D D C-(二分)
        fp(1,2,t:4), fp(1,2,t:4), fp(1,0,t:8),
      ]),
    ],
  ),

  // ═══ 2. 两只老虎 (Frère Jacques) ═══
  // 经典轮唱曲,旋律重复、级进,指弹入门。
  // 旋律:mi re do mi | mi re do mi | mi fa sol— | mi fa sol— |
  //      sol la sol fa mi re do | sol la sol fa mi re do | sol mi do— | sol mi do—
  FingerpickSong(
    title: '两只老虎 (Frère Jacques)',
    subtitle: 'C 调 · 指弹入门',
    tempo: 90,
    bars: [
      FingerpickBar(lyric: '两只老虎', slots: [ // mi re do mi
        fp(2,0,t:4), fp(1,2,t:4), fp(1,0,t:4), fp(2,0,t:4),
      ]),
      FingerpickBar(lyric: '两只老虎', slots: [ // mi re do mi
        fp(2,0,t:4), fp(1,2,t:4), fp(1,0,t:4), fp(2,0,t:4),
      ]),
      FingerpickBar(lyric: '跑得快', slots: [ // mi fa sol(二分)
        fp(2,0,t:4), fp(2,1,t:4), fp(0,0,t:8),
      ]),
      FingerpickBar(lyric: '跑得快', slots: [ // mi fa sol(二分)
        fp(2,0,t:4), fp(2,1,t:4), fp(0,0,t:8),
      ]),
      FingerpickBar(lyric: '一只没有耳朵', slots: [ // sol la sol fa mi re do(前6个8分 + do四分)
        fp(0,0,t:2), fp(3,0,t:2), fp(0,0,t:2), fp(2,1,t:2), fp(2,0,t:2), fp(1,2,t:2), fp(1,0,t:4),
      ]),
      FingerpickBar(lyric: '一只没有尾巴', slots: [ // sol la sol fa mi re do
        fp(0,0,t:2), fp(3,0,t:2), fp(0,0,t:2), fp(2,1,t:2), fp(2,0,t:2), fp(1,2,t:2), fp(1,0,t:4),
      ]),
      FingerpickBar(lyric: '真奇怪', slots: [ // sol mi do(二分)
        fp(0,0,t:4), fp(2,0,t:4), fp(1,0,t:8),
      ]),
      FingerpickBar(lyric: '真奇怪', slots: [ // sol mi do(二分)
        fp(0,0,t:4), fp(2,0,t:4), fp(1,0,t:8),
      ]),
    ],
  ),

  // ═══ 3. 欢乐颂 (Ode to Joy) ═══
  // 贝多芬《第九交响曲》主题,旋律稳、全级进,指弹入门经典。
  // 旋律:mi mi fa sol | sol fa mi re | do do re mi | mi re re— |
  //      mi mi fa sol | sol fa mi re | do do re mi | re do do—
  FingerpickSong(
    title: '欢乐颂 (Ode to Joy)',
    subtitle: '贝多芬 · C 调指弹',
    tempo: 95,
    bars: [
      FingerpickBar(lyric: '欢乐女神', slots: [ // mi mi fa sol
        fp(2,0,t:4), fp(2,0,t:4), fp(2,1,t:4), fp(0,0,t:4),
      ]),
      FingerpickBar(lyric: '圣洁美丽', slots: [ // sol fa mi re
        fp(0,0,t:4), fp(2,1,t:4), fp(2,0,t:4), fp(1,2,t:4),
      ]),
      FingerpickBar(lyric: '灿烂光芒', slots: [ // do do re mi
        fp(1,0,t:4), fp(1,0,t:4), fp(1,2,t:4), fp(2,0,t:4),
      ]),
      FingerpickBar(lyric: '照大地', slots: [ // mi re re(二分)
        fp(2,0,t:4), fp(1,2,t:4), fp(1,2,t:8),
      ]),
      FingerpickBar(lyric: '我们心中', slots: [ // mi mi fa sol
        fp(2,0,t:4), fp(2,0,t:4), fp(2,1,t:4), fp(0,0,t:4),
      ]),
      FingerpickBar(lyric: '充满热情', slots: [ // sol fa mi re
        fp(0,0,t:4), fp(2,1,t:4), fp(2,0,t:4), fp(1,2,t:4),
      ]),
      FingerpickBar(lyric: '来到你的', slots: [ // do do re mi
        fp(1,0,t:4), fp(1,0,t:4), fp(1,2,t:4), fp(2,0,t:4),
      ]),
      FingerpickBar(lyric: '圣殿里', slots: [ // re do do(二分)
        fp(1,2,t:4), fp(1,0,t:4), fp(1,0,t:8),
      ]),
    ],
  ),

  // ═══ 更多入门儿歌(旋律全球熟知,指弹入门) ═══
  // 音高沿用上面儿歌的 C 调指法:do=C弦空(1,0) re=C弦2品(1,2) mi=E弦空(2,0)
  //   fa=E弦1品(2,1) sol=G弦空(0,0) la=A弦空(3,0) do'=A弦3品(3,3)
  //   re'=A弦5品(3,5) mi'=A弦7品(3,7)。每小节 4 拍 = 16 个 16 分 tick。

  // ═══ 4. Mary Had a Little Lamb (玛丽有只小羊羔) ═══
  // 全曲只用 mi re do sol 四个音,最简单的入门旋律之一。
  // 旋律:mi re do re mi mi mi | re re re | mi sol sol | mi re do re mi mi mi | mi re do re mi re do
  FingerpickSong(
    title: '玛丽有只小羊羔 (Mary Had a Little Lamb)',
    subtitle: 'C 调 · 指弹入门',
    tempo: 95,
    bars: [
      FingerpickBar(lyric: 'Mary had a', slots: [ // mi re do re mi mi mi
        fp(2,0,t:2), fp(1,2,t:2), fp(1,0,t:2), fp(1,2,t:2), fp(2,0,t:2), fp(2,0,t:2), fp(2,0,t:4),
      ]),
      FingerpickBar(lyric: 'little lamb', slots: [ // re re re(二分)
        fp(1,2,t:4), fp(1,2,t:4), fp(1,2,t:8),
      ]),
      FingerpickBar(lyric: 'little lamb', slots: [ // mi sol sol(二分)
        fp(2,0,t:4), fp(0,0,t:4), fp(0,0,t:8),
      ]),
      FingerpickBar(lyric: 'Mary had a', slots: [ // mi re do re mi mi mi
        fp(2,0,t:2), fp(1,2,t:2), fp(1,0,t:2), fp(1,2,t:2), fp(2,0,t:2), fp(2,0,t:2), fp(2,0,t:4),
      ]),
      FingerpickBar(lyric: 'fleece white as snow', slots: [ // mi re do re mi re do(收尾)
        fp(2,0,t:2), fp(1,2,t:2), fp(1,0,t:2), fp(1,2,t:2), fp(2,0,t:2), fp(1,2,t:2), fp(1,0,t:4),
      ]),
    ],
  ),

  // ═══ 5. London Bridge (伦敦桥) ═══
  // 经典英国儿歌,旋律起伏明显、练换弦。
  // 旋律:sol la sol fa mi fa sol | re mi fa mi fa sol | sol la sol fa mi fa sol | sol mi do
  FingerpickSong(
    title: '伦敦桥 (London Bridge)',
    subtitle: 'C 调 · 指弹入门',
    tempo: 100,
    bars: [
      FingerpickBar(lyric: 'London Bridge', slots: [ // sol la sol fa mi fa sol
        fp(0,0,t:2), fp(3,0,t:2), fp(0,0,t:2), fp(2,1,t:2), fp(2,0,t:2), fp(2,1,t:2), fp(0,0,t:4),
      ]),
      FingerpickBar(lyric: 'falling down', slots: [ // re mi fa mi fa sol(附点收尾)
        fp(1,2,t:2), fp(2,0,t:2), fp(2,1,t:2), fp(2,0,t:2), fp(2,1,t:2), fp(0,0,t:6),
      ]),
      FingerpickBar(lyric: 'London Bridge', slots: [ // sol la sol fa mi fa sol
        fp(0,0,t:2), fp(3,0,t:2), fp(0,0,t:2), fp(2,1,t:2), fp(2,0,t:2), fp(2,1,t:2), fp(0,0,t:4),
      ]),
      FingerpickBar(lyric: 'my fair lady', slots: [ // sol mi do(二分收尾)
        fp(0,0,t:4), fp(2,0,t:4), fp(1,0,t:8),
      ]),
    ],
  ),

  // ═══ 6. Jingle Bells (铃儿响叮当 · 副歌循环) ═══
  // 只取最洗脑的副歌开头三小节,自然循环回开头,适合反复练。
  // 旋律:mi mi mi | mi mi mi | mi sol do re mi(后三音爬到高音,用到第7品)
  FingerpickSong(
    title: '铃儿响叮当 (Jingle Bells · 副歌)',
    subtitle: 'C 调 · 副歌循环 · 用到第7品',
    tempo: 120,
    bars: [
      FingerpickBar(lyric: 'Jingle bells', slots: [ // mi mi mi(二分)
        fp(2,0,t:4), fp(2,0,t:4), fp(2,0,t:8),
      ]),
      FingerpickBar(lyric: 'Jingle bells', slots: [ // mi mi mi(二分)
        fp(2,0,t:4), fp(2,0,t:4), fp(2,0,t:8),
      ]),
      FingerpickBar(lyric: 'jingle all the way', slots: [ // mi sol do' re' mi'(爬到高音)
        fp(2,0,t:2), fp(0,0,t:2), fp(3,3,t:2), fp(3,5,t:2), fp(3,7,t:8),
      ]),
    ],
  ),

  // ═══ 经典指弹曲(原 3 首,稍难) ═══
  // ═══ Canon in C (卡农 C 调简化版) ═══
  // 基于经典和声进行:C—G—Am—Em—F—C—F—G,旋律在 A/E 弦上、低音在 G/C 弦伴奏。
  // tempo 80, 4/4 拍,每小节 8 个 8 分音符槽(= 8×dur=2)。
  FingerpickSong(
    title: 'Canon in C (卡农)',
    subtitle: 'Pachelbel · C 调指弹改编',
    tempo: 80,
    bars: [
      // 第1小节 C:旋律 E-D-C,低音 C-G
      FingerpickBar(lyric: 'C', slots: [
        fp(3,3,t:2), fp(2,0,t:2), fp(2,0,t:2), fp(1,0,t:2), // G弦3品 C→E空→E空→C空
        fp(2,0,t:2), fpr(t:2), fp(0,3,t:2), fpr(t:2),        // E空→休→A3品→休
      ]),
      // 第2小节 G:旋律 G-F-E,低音 G-B
      FingerpickBar(lyric: 'G', slots: [
        fp(3,2,t:2), fp(2,0,t:2), fp(1,0,t:2), fp(3,3,t:2),
        fp(1,0,t:2), fpr(t:2), fp(0,2,t:2), fpr(t:2),
      ]),
      // 第3小节 Am:旋律 A-C-E,低音 A-E
      FingerpickBar(lyric: 'Am', slots: [
        fp(0,0,t:2), fp(2,0,t:2), fp(2,0,t:2), fp(1,0,t:2),
        fp(2,0,t:2), fpr(t:2), fp(0,0,t:2), fpr(t:2),
      ]),
      // 第4小节 Em:旋律 G-F#-E,低音 E-B
      FingerpickBar(lyric: 'Em', slots: [
        fp(3,2,t:2), fp(2,0,t:2), fp(1,0,t:2), fp(3,3,t:2),
        fp(1,0,t:2), fpr(t:2), fp(0,2,t:2), fpr(t:2),
      ]),
      // 第5小节 F:旋律 F-A-C,低音 F-C
      FingerpickBar(lyric: 'F', slots: [
        fp(3,1,t:2), fp(2,1,t:2), fp(1,0,t:2), fp(3,2,t:2),
        fp(2,1,t:2), fpr(t:2), fp(0,1,t:2), fpr(t:2),
      ]),
      // 第6小节 C:旋律 E-D-C,低音 C-G
      FingerpickBar(lyric: 'C', slots: [
        fp(3,3,t:2), fp(2,0,t:2), fp(1,0,t:2), fp(3,3,t:2),
        fp(2,0,t:2), fpr(t:2), fp(0,3,t:2), fpr(t:2),
      ]),
      // 第7小节 F:旋律 F-G-A,低音 F-C
      FingerpickBar(lyric: 'F', slots: [
        fp(3,1,t:2), fp(2,1,t:2), fp(1,0,t:2), fp(3,2,t:2),
        fp(3,3,t:2), fp(2,0,t:2), fp(0,1,t:2), fpr(t:2),
      ]),
      // 第8小节 G→回头:旋律 G-F-E-D,低音 G-D
      FingerpickBar(lyric: 'G', slots: [
        fp(3,2,t:2), fp(2,0,t:2), fp(1,0,t:2), fp(3,3,t:2),
        fp(1,0,t:2), fp(2,0,t:2), fp(0,2,t:2), fpr(t:2),
      ]),
    ],
  ),

  // ═══ 2. Greensleeves (绿袖子) ═══
  // 英国传统民谣,Am 调。原曲 6/8 拍,这里按 4/4 改编(每小节 16 个 16 分 tick,8 个 8 分音符)。
  FingerpickSong(
    title: 'Greensleeves (绿袖子)',
    subtitle: '英国传统民谣 · Am 调',
    tempo: 90,
    bars: [
      // 第1小节 Am:旋律 A-C-E-D-C-A
      FingerpickBar(lyric: 'Am · Alas my love', slots: [
        fp(0,0,t:2), fp(2,0,t:2), fp(2,0,t:2), fp(1,2,t:2), // A空→E空→E空→C2品
        fp(0,0,t:2), fpr(t:2), fp(3,2,t:2), fpr(t:2),
      ]),
      // 第2小节 G:旋律 G-A-C-A-F#-G
      FingerpickBar(lyric: 'G · you do me wrong', slots: [
        fp(0,2,t:2), fp(3,2,t:2), fp(0,0,t:2), fp(2,0,t:2),
        fp(1,0,t:2), fpr(t:2), fp(3,2,t:2), fpr(t:2),
      ]),
      // 第3小节 Am:旋律 A-C-E-D-C
      FingerpickBar(lyric: 'Am · to cast me off', slots: [
        fp(0,0,t:2), fp(2,0,t:2), fp(2,0,t:2), fp(1,2,t:2),
        fp(0,0,t:2), fpr(t:2), fp(2,0,t:2), fpr(t:2),
      ]),
      // 第4小节 E:旋律 E-F#-G#-A-B
      FingerpickBar(lyric: 'E · discourteously', slots: [
        fp(0,2,t:2), fp(3,1,t:2), fp(0,1,t:2), fp(2,1,t:2),
        fp(1,2,t:2), fpr(t:2), fp(3,2,t:2), fpr(t:2),
      ]),
      // 第5小节 C:旋律 C-E-D-C-A
      FingerpickBar(lyric: 'C · I have loved you', slots: [
        fp(3,3,t:2), fp(2,0,t:2), fp(1,0,t:2), fp(2,0,t:2),
        fp(0,3,t:2), fpr(t:2), fp(2,0,t:2), fpr(t:2),
      ]),
      // 第6小节 G:旋律 G-A-C-A
      FingerpickBar(lyric: 'G · so long', slots: [
        fp(0,2,t:2), fp(3,2,t:2), fp(0,0,t:2), fp(2,0,t:2),
        fp(1,0,t:2), fpr(t:2), fp(3,2,t:2), fpr(t:2),
      ]),
      // 第7小节 Am→E:旋律 A-B-C-C-B-A
      FingerpickBar(lyric: 'Am E · delighting in', slots: [
        fp(0,0,t:2), fp(3,2,t:2), fp(2,0,t:2), fp(1,2,t:2),
        fp(3,0,t:2), fp(2,0,t:2), fp(0,1,t:2), fpr(t:2),
      ]),
      // 第8小节 Am:旋律 E-C-A 收尾
      FingerpickBar(lyric: 'Am · your company', slots: [
        fp(2,0,t:2), fp(1,2,t:2), fp(0,0,t:2), fpr(t:2),
        fp(3,2,t:2), fpr(t:2), fp(0,0,t:2), fpr(t:2),
      ]),
    ],
  ),

  // ═══ 第16步:PD 传统儿歌指弹 2 首(旋律全球熟知、音域窄、全在 0-5 品新手够得到) ═══
  // C 调指法沿用:do=C弦空(1,0) re=C弦2品(1,2) mi=E弦空(2,0) fa=E弦1品(2,1)
  //   sol=G弦空(0,0) la=A弦空(3,0) do'=A弦3品(3,3)。每小节 4 拍 = 16 个 16 分 tick(duration 和必须 = 16)。
  // 旋律由本 app 扒谱(Claude 凭熟知旋律逐音落 fp),装机若个别音不准,用户反馈即改。

  // Row Row Row Your Boat(划小船)—— 英国传统儿歌(PD),旋律极简、音域 do-sol。
  // 旋律:do re mi do | mi fa sol | sol la sol fa mi do | do sol do
  FingerpickSong(
    title: '划小船 (Row Row Row Your Boat)',
    subtitle: '传统儿歌 · C 调 · 指弹入门',
    tempo: 100,
    bars: [
      FingerpickBar(lyric: 'Row row row your boat', slots: [ // do re mi do
        fp(1,0,t:4), fp(1,2,t:4), fp(2,0,t:4), fp(1,0,t:4),
      ]),
      FingerpickBar(lyric: 'gently down the stream', slots: [ // mi fa sol(二分收)
        fp(2,0,t:4), fp(2,1,t:4), fp(0,0,t:8),
      ]),
      FingerpickBar(lyric: 'merrily merrily...', slots: [ // sol la sol fa mi do(八分切分)
        fp(0,0,t:2), fp(3,0,t:2), fp(0,0,t:2), fp(2,1,t:2), fp(2,0,t:4), fp(1,0,t:4),
      ]),
      FingerpickBar(lyric: 'life is but a dream', slots: [ // do sol do(二分收尾)
        fp(1,0,t:4), fp(0,0,t:4), fp(1,0,t:8),
      ]),
    ],
  ),

  // Old MacDonald(老麦克唐纳)—— 美国传统儿歌(PD),含招牌 "E-I-E-I-O"。
  // 旋律:Old MacDonald had a farm = sol sol sol mi mi do;E-I-E-I-O = mi do' mi do' sol。
  FingerpickSong(
    title: '老麦克唐纳 (Old MacDonald)',
    subtitle: '传统儿歌 · C 调 · 指弹入门',
    tempo: 100,
    bars: [
      FingerpickBar(lyric: 'Old MacDonald', slots: [ // sol sol sol mi mi do(八分+四分)
        fp(0,0,t:2), fp(0,0,t:2), fp(0,0,t:4), fp(2,0,t:2), fp(2,0,t:2), fp(1,0,t:4),
      ]),
      FingerpickBar(lyric: 'had a farm', slots: [ // sol mi do(长收)
        fp(0,0,t:4), fp(2,0,t:4), fp(1,0,t:8),
      ]),
      FingerpickBar(lyric: 'E I E I O', slots: [ // mi do' mi do' sol(八分跳进 + 长收)
        fp(2,0,t:2), fp(3,3,t:2), fp(2,0,t:2), fp(3,3,t:2), fp(0,0,t:8),
      ]),
      FingerpickBar(lyric: 'Old MacDonald', slots: [ // sol sol sol mi mi do(再现)
        fp(0,0,t:2), fp(0,0,t:2), fp(0,0,t:4), fp(2,0,t:2), fp(2,0,t:2), fp(1,0,t:4),
      ]),
      FingerpickBar(lyric: 'had a farm', slots: [ // fa fa mi re do(收尾)
        fp(2,1,t:2), fp(2,1,t:2), fp(2,0,t:4), fp(1,2,t:4), fp(1,0,t:4),
      ]),
    ],
  ),
];

// —— 琶音织体练习(独立 tab) ——
// 跟 Song(扫弦弹唱)、FingerpickSong(旋律 TAB)都不同:琶音是在【一个和弦上按顺序拨弦】的伴奏织体,
// 不是旋律。练的是右手拨弦顺序(4321 / 4323 这类)。一首"练习"= 一组和弦进行 + 反复套拨弦型。
// 弦下标跟全仓统一:0=G,1=C,2=E,3=A。物理弦号显示 = 4 - stringIndex(0→"4"…3→"1")。

/// 琶音拨弦型:在某个和弦上反复拨的弦序。
@immutable
class ArpPattern {
  final String name;          // '4321 琶音'
  final List<int> strings;    // stringIndex 序列(0=G 1=C 2=E 3=A),按此循环拨
  final int notesPerBeat;     // 一拍几个音:1=四分(慢琶音,一拍一音) 2=八分(流动织体)

  const ArpPattern({required this.name, required this.strings, required this.notesPerBeat});
}

/// 一条琶音练习:一组和弦进行,反复套拨弦型练。
@immutable
class ArpStudy {
  final String title;         // '流行进行'
  final String? subtitle;     // '1-5-6-4 · C G Am F · 最常用'
  final List<String> chords;  // 和弦名序列(都需在 chordShapes 里,才能画图 + playString)
  final int beatsPerChord;    // 一个和弦持续几拍
  final int tempo;            // 建议 BPM

  const ArpStudy({
    required this.title,
    this.subtitle,
    required this.chords,
    this.beatsPerChord = 4,
    required this.tempo,
  });
}

/// 半拍槽 slot(0..beatsPerChord*2-1,偶数=正拍前半,奇数=后半) → 该拨哪根弦(stringIndex);
/// 返回 null 表示该槽不拨(一拍一音型的后半拍是空,留给上一音延续)。
/// 每个和弦从 pattern[0] 起(和弦第一拍落在低音 G 上,符合伴奏习惯)。
/// notesPerBeat==1:只在正拍(偶数槽)拨,arpIndex = slot~/2;
/// notesPerBeat==2:每槽都拨,arpIndex = slot。
int? arpStringAt(ArpPattern p, int beatsPerChord, int slot) {
  if (slot < 0) return null;
  if (p.notesPerBeat == 1) {
    if (slot.isOdd) return null; // 后半拍不拨
    final beatWithinChord = slot ~/ 2;
    return p.strings[beatWithinChord % p.strings.length];
  }
  // notesPerBeat == 2(八分):每个半拍槽拨一下
  return p.strings[slot % p.strings.length];
}

// —— 内置琶音拨弦型 ——
// 弦号按物理弦序命名(4=G…1=A),跟和弦速查页 / 调音器一致,新手一看就懂拨哪根。
// 所有型 strings[0] 都是 0(G 低音):每个和弦第一拍都落在低音上,符合伴奏习惯,也锁住不变量。
// 4321:最经典琶音,一拍一音(四分),一小节正好从低到高滚一遍(G→C→E→A)。
// 4323:伴奏最常用织体,八分音符流动(4-3-2-3 循环)。
// 上下行:八分流动,一小节先上行 4321 再下行 1234(G C E A A E C G),抒情伴奏最常用,一满小节一个完整来回。
// 4123:一拍一音,先拨低音 G、再从最高音 A 往下走(G A E C),"外向内"轮廓,跟 4321(纯上行)对比明显。
// 4313:八分织体,4-3-1-3 循环(G C A C),高点落在 A 弦上、比 4323(高点 E)色彩更亮更跳。
const builtinArpPatterns = <ArpPattern>[
  ArpPattern(name: '4321 琶音', strings: [0, 1, 2, 3], notesPerBeat: 1),
  ArpPattern(name: '4323 织体', strings: [0, 1, 2, 1], notesPerBeat: 2),
  ArpPattern(name: '上下行 织体', strings: [0, 1, 2, 3, 3, 2, 1, 0], notesPerBeat: 2),
  ArpPattern(name: '4123 琶音', strings: [0, 3, 2, 1], notesPerBeat: 1),
  ArpPattern(name: '4313 织体', strings: [0, 1, 3, 1], notesPerBeat: 2),
];

// —— 内置琶音练习(几条最常用和弦进行,都 C/Am 调) ——
// 单和弦慢练放第一个:初学先在一个和弦上把拨弦型练熟,再加换和弦。
const builtinArpStudies = <ArpStudy>[
  ArpStudy(title: '单和弦慢练', subtitle: 'C · 先把右手拨弦练均匀', chords: ['C'], tempo: 70),
  ArpStudy(title: '流行进行', subtitle: '1-5-6-4 · C G Am F · 最常用', chords: ['C', 'G', 'Am', 'F'], tempo: 72),
  ArpStudy(title: '经典进行', subtitle: '1-6-4-5 · C Am F G', chords: ['C', 'Am', 'F', 'G'], tempo: 72),
  ArpStudy(title: '小调色彩', subtitle: '6-4-1-5 · Am F C G', chords: ['Am', 'F', 'C', 'G'], tempo: 72),
  // —— 真歌进行(拿流行/经典歌的真实和弦进行练琶音伴奏,比抽象进行好玩、有辨识度)——
  // 和弦都取自 chordShapes,arpeggio_test 会卡住写错和弦名的。
  ArpStudy(title: '🌙 月亮代表我的心', subtitle: '邓丽君 · C Em Am F', chords: ['C', 'Em', 'Am', 'F'], tempo: 72),
  ArpStudy(title: '🤝 朋友', subtitle: '周华健 · G 调 · G Em C D', chords: ['G', 'Em', 'C', 'D'], tempo: 88),
  ArpStudy(title: '🍃 遇见', subtitle: '孙燕姿 · C G Am Em F G(6 和弦)', chords: ['C', 'G', 'Am', 'Em', 'F', 'G'], tempo: 76),
  ArpStudy(title: '☀️ You Are My Sunshine', subtitle: '乡村经典 · C G7(2 和弦)', chords: ['C', 'G7', 'C', 'G7'], tempo: 90),
  ArpStudy(title: '🌅 Counting Stars', subtitle: 'OneRepublic · Am C G F', chords: ['Am', 'C', 'G', 'F'], tempo: 100),
  ArpStudy(title: "💕 Can't Help Falling in Love", subtitle: 'Elvis · C Em Am F G', chords: ['C', 'Em', 'Am', 'F', 'G'], tempo: 66),
];

// —— 换和弦训练·多和弦(新功能Step16) ——
// 一条换和弦训练预设:命名的经典进行,一键塞进训练页当序列练。
@immutable
class TrainerPreset {
  final String name;         // '万能四和弦'
  final String hint;         // 'C-G-Am-F · 1-5-6-4,流行歌万能套'
  final List<String> chords; // 和弦序列(每个都在 chordShapes 里、线性相邻不重复)

  const TrainerPreset({required this.name, required this.hint, required this.chords});
}

// 四条最经典的进行(都 C 调、都由三和弦构成,新手够用;琶音页的 builtinArpStudies 前 3 条同源)。
// trainer_logic_test 有合法性卡口:和弦名必须在 chordShapes 里、相邻不重复,写错测试直接红。
const trainerPresets = <TrainerPreset>[
  TrainerPreset(name: '万能四和弦', hint: 'C-G-Am-F · 1-5-6-4,大部分流行歌都能套', chords: ['C', 'G', 'Am', 'F']),
  TrainerPreset(name: '50年代', hint: 'C-Am-F-G · 1-6-4-5,经典抒情', chords: ['C', 'Am', 'F', 'G']),
  TrainerPreset(name: '卡农进行', hint: 'C-G-Am-Em-F-C-F-G · 8 个和弦', chords: ['C', 'G', 'Am', 'Em', 'F', 'C', 'F', 'G']),
  TrainerPreset(name: '1-4-5', hint: 'C-F-G · 最基础的三和弦', chords: ['C', 'F', 'G']),
];

/// 换和弦训练:该切到序列里第几个了(新功能Step16)。纯函数,随机性由调用方传 Random
/// (无头测试能锁行为,跟 nextRampTempo 一个套路)。
/// 顺序模式:下一个下标,越过末尾转圈。
/// 随机模式:挑一个 ≠ 当前的——偏移法(rnd 出 0..len-2,大于等于当前就 +1 跳过自己),
/// 一步到位且每个位置等概率,不用"抽到相同就重抽"的拒绝循环(理论上会转很多圈)。
int nextTrainerIndex(int len, int idx, {required bool random, required Random rnd}) {
  if (len < 2) return idx; // 序列退化(不该发生,编辑/载入都保证 ≥2)→ 不动,防崩
  if (!random) return (idx + 1) % len;
  final j = rnd.nextInt(len - 1);
  return j >= idx ? j + 1 : j;
}

/// 清洗存的换和弦序列(新功能Step16):去掉 chordShapes 里没有的(以后删和弦防失效)
/// + 去掉线性相邻重复(相邻相同 = 切了等于没切,计数虚加、切和弦动画也不触发)。
/// 清完不足 2 个 → 返回空表,调用方走 fallback(老键迁移 / 随机抽)。
/// 注意:只去"相邻"重复——序列里允许同一和弦出现多次(卡农里 C 就有两次),那是合法的。
List<String> sanitizeTrainerChords(List<String> raw) {
  final out = <String>[];
  for (final c in raw) {
    if (!chordShapes.containsKey(c)) continue; // 指法没了的和弦直接丢
    if (out.isNotEmpty && out.last == c) continue; // 跟前一个一样 → 丢这个
    out.add(c);
  }
  return out.length < 2 ? const [] : out;
}
