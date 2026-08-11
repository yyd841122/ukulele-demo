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
/// 「海岛」(Island/Calypso):D - D U - U D U——尤克里里最招牌的节奏,练熟它能弹一大半流行歌。
/// 「民谣」(Folk):D - D U U - D U——民谣弹唱常用,比海岛多一个正拍下扫、更稳。
/// 「摇滚」:D - D U D U D U——密集连续扫,鼓点感强、推得动。
///   全下 / 下上 按拍数【动态生成】,任何拍数都正常。
///   海岛 / 民谣 / 摇滚 按 4 拍(8 槽)写死(第51步起):非 4 拍歌(如 3 拍华尔兹)不返回它们——
///   否则 grid 会截断、形状怪;而且这仨本就是 4/4 招牌节奏,硬塞别的拍数也不合乐理。非 4 拍只给前两个。
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
  ];
  // 4 拍才给三个招牌节奏(它们按 8 槽写死,别的拍数会截断 / 不合乐理)。
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
/// 原 IZ 版把《Over the Rainbow》和《What a Wonderful World》串成一首串烧(medley),
/// 这里按"两首就该分两条"的原则拆成两首,免得新手以为后半段是《Over the Rainbow》的词。
/// 歌词用行内和弦([C]词),比 Web 版(和弦单独一排)更清楚和弦落在哪个词上。
///
/// 第52步:加 6 首中文经典/流行歌(月亮代表我的心 / 童年 / 那些花儿 / 后来 / 朋友 / 童话),
/// 都选和弦简单、传唱度高的,新手友好;和弦从扩过的 20 个 chordShapes 里取。同时把老注释里
/// "6 个和弦"改成不写死数量——和弦表在持续扩充,数字注释容易过时。
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
  // —— 第52步:中文经典/流行歌曲(6 首,和弦都从扩过的 20 个 chordShapes 里取,新手友好)——
  Song(
    title: "🌙 月亮代表我的心",
    tempo: 72,
    beatsPerChord: 4,
    sections: [
      Section(
        name: '主歌',
        lines: [
          Line(lyric: "[C]你问我爱你[Em]有多深,我[Am]爱你有几[F]分"),
          Line(lyric: "[C]我的情也[Em]真,我的[Dm]爱也[G7]真"),
          Line(lyric: "[C]你问我爱你[Em]有多深,我[Am]爱你有几[F]分"),
          Line(lyric: "[C]我的情不[Em]移,我的[Dm]爱不[G7]变,月亮[C]代表[F]我的[C]心"),
        ],
      ),
      Section(
        name: '🎶 副歌',
        lines: [
          Line(lyric: "[Am]轻[F]轻的一个[C]吻,已经打动我的心"),
          Line(lyric: "[Am]深[F]深的一段[C]情,教我思念到如今"),
          Line(lyric: "[C]你问我爱你[Em]有多深,我[Am]爱你有几[F]分"),
          Line(lyric: "[C]你去想一[Em]想,你去[Dm]看一[G7]看,月亮[C]代表[F]我的[C]心"),
        ],
      ),
    ],
  ),
  Song(
    title: "👦 童年",
    tempo: 120,
    beatsPerChord: 4,
    sections: [
      Section(
        name: '主歌',
        lines: [
          Line(lyric: "[C]池塘边的[Am]榕树上,知了在[F]声声地叫[G]着夏天"),
          Line(lyric: "[C]操场边的[Am]秋千上,只有那[F]蝴蝶停在[G]上面"),
          Line(lyric: "[C]黑板上老师[Am]的粉笔,还在拼命[F]叽叽喳喳[G]写个不停"),
          Line(lyric: "[C]等待着下课[Am]等待着放学,等待[F]游戏的[G]童年"),
        ],
      ),
      Section(
        name: '🎶 副歌',
        lines: [
          Line(lyric: "[C]喔—[Am]一天又一天,[F]一年又一[G]年"),
          Line(lyric: "[C]盼望着长[Am]大的[F]童[G]年"),
        ],
      ),
    ],
  ),
  Song(
    title: "🌸 那些花儿",
    tempo: 80,
    beatsPerChord: 4,
    sections: [
      Section(
        name: '主歌',
        lines: [
          Line(lyric: "[C]那片笑声让我[G]想起,我的[Am]那些花[F]儿"),
          Line(lyric: "[C]在我生命每个[G]角落,静静[Am]为我开[F]着"),
          Line(lyric: "[C]我曾以为我会[G]永远,守在[Am]她身[F]旁"),
          Line(lyric: "[C]今天我们[G]已经离去,在人[Am]海茫[F]茫"),
        ],
      ),
      Section(
        name: '🎶 副歌',
        lines: [
          Line(lyric: "[C]她们都老了[G]吧,她们[Am]在哪里[F]呀"),
          Line(lyric: "[C]幸运的[G]是,我曾陪她[Am]们开[F]放"),
          Line(lyric: "[C]啦…[G]啦…[Am]啦…想[F]她"),
          Line(lyric: "[C]啦…[G]啦…[Am]她还在开[F]吗"),
        ],
      ),
    ],
  ),
  Song(
    title: "💫 后来",
    tempo: 76,
    beatsPerChord: 4,
    sections: [
      Section(
        name: '主歌',
        lines: [
          Line(lyric: "[C]后来,我总算[Am]学会了如何去[F]爱"),
          Line(lyric: "[C]可惜你早已[Am]远去,消失在[F]人[G]海"),
          Line(lyric: "[C]后来,终于在[Am]眼泪中明[F]白"),
          Line(lyric: "[C]有些人[Am]一旦[F]错过就[G]不再"),
        ],
      ),
      Section(
        name: '🎶 副歌',
        lines: [
          Line(lyric: "[C]栀子花[Am]白花[F]瓣,落在你[G]蓝色百褶裙上"),
          Line(lyric: "[C]爱你,你[Am]轻声[F]说,我低[G]下头闻见一阵芬芳"),
          Line(lyric: "[C]那个永恒的[Am]夜晚,十七岁[F]仲夏,你吻我[G]的那个夜晚"),
          Line(lyric: "[Em]让我往后的[Am]时光,每当有[F]感叹,总想起[G]当天的星光"),
          Line(lyric: "[C]你都如何[Am]回忆[F]我,带着笑[G]或是很沉默"),
          Line(lyric: "[C]这些年[Am]来,有没有[F]人能让你[G]不寂[C]寞"),
        ],
      ),
    ],
  ),
  Song(
    title: "🤗 朋友",
    tempo: 98,
    beatsPerChord: 4,
    sections: [
      Section(
        name: '主歌',
        lines: [
          Line(lyric: "[G]这些年[Em]一个人,[C]风也过[D]雨也走"),
          Line(lyric: "[G]有过泪[Em]有过错,[C]还记得坚持[D]什么"),
          Line(lyric: "[G]真爱过[Em]才会懂,[C]会寂寞[D]会回首"),
          Line(lyric: "[G]终有梦[Em]终有你,[C]在心[D]中"),
        ],
      ),
      Section(
        name: '🎶 副歌',
        lines: [
          Line(lyric: "[G]朋友[Em]一生一起走,[C]那些日子[D]不再有"),
          Line(lyric: "[G]一句话[Em]一辈子,[C]一生情[D]一杯酒"),
          Line(lyric: "[G]朋友[Em]不曾孤单过,[C]一声朋友[D]你会懂"),
          Line(lyric: "[G]还有伤[Em]还有痛,[C]还要走[D]还有[G]我"),
        ],
      ),
    ],
  ),
  Song(
    title: "🧚 童话",
    tempo: 70,
    beatsPerChord: 4,
    sections: [
      Section(
        name: '主歌',
        lines: [
          Line(lyric: "[C]忘了有多久,[Am]再没听到[F]你,对我说[G]你最爱的故事"),
          Line(lyric: "[C]我想了很久,[Am]我开始慌[F]了,是不是我[G]又做错了什么"),
          Line(lyric: "[C]你哭着对我[Am]说,童话里[F]都是骗人[G]的"),
          Line(lyric: "[Em]我不可能,[Am]是你的[Dm]王[G7]子"),
        ],
      ),
      Section(
        name: '🎶 副歌',
        lines: [
          Line(lyric: "[C]也许你不会[Am]懂,从你说爱我[F]以后,我的[G]天空星星都亮了"),
          Line(lyric: "[C]我愿变成[Am]童话里,[F]你爱的那[G]个天使"),
          Line(lyric: "[Em]张开双手,[Am]变成翅膀[Dm]守护[G7]你"),
          Line(lyric: "[F]你要相信,[G]相信我们会[Em]像童话[Am]故事里"),
          Line(lyric: "[F]幸福和[G]快乐是结[C]局"),
        ],
      ),
    ],
  ),

  // —— 第54步:新加 7 首(4 英文 + 3 中文),含一首 3/4 拍 ——

  Song(
    title: '🐦 Three Little Birds',
    tempo: 74,
    beatsPerChord: 4,
    sections: [
      Section(
        name: '主歌',
        lines: [
          Line(lyric: "[A]Don't worry about a thing"),
          Line(lyric: "[D]Cause every little thing [A]gonna be alright"),
          Line(lyric: "[A]Singin' don't worry about a thing"),
          Line(lyric: "[D]Cause every little thing [A]gonna be alright"),
        ],
      ),
      Section(
        name: '🎶 副歌',
        lines: [
          Line(lyric: "[A]Rise up this mornin', smiled with the [D]risin' sun"),
          Line(lyric: "[A]Three little birds perched [D]by my [A]doorstep"),
          Line(lyric: "[A]Singin' sweet songs of [D]melodies pure and [A]true"),
          Line(lyric: "[A]Sayin' this is my [D]message to [A]you"),
        ],
      ),
    ],
  ),
  Song(
    title: '🎵 Hallelujah',
    tempo: 66,
    beatsPerChord: 4,
    sections: [
      Section(
        name: '主歌',
        lines: [
          Line(lyric: "[C]Now I've [Am]heard there was a [C]secret [Am]chord"),
          Line(lyric: "[C]That [F]David played and it [G]pleased the [C]Lord"),
          Line(lyric: "[F]But [G]you don't really [C]care for [Am]music, [F]do [G]ya"),
          Line(lyric: "[C]It goes [F]like this, the [G]fourth, the [Am]fifth"),
          Line(lyric: "[F]The minor [G]fall, the [E7]major [Am]lift"),
          Line(lyric: "[F]The baffled king com[G]posing Halle[C]lujah"),
        ],
      ),
      Section(
        name: '🎶 副歌',
        lines: [
          Line(lyric: "[C]Halle[Am]lujah, [C]Halle[Am]lujah"),
          Line(lyric: "[C]Halle[F]lujah, [G]Halle[C]lu[G]jah"),
        ],
      ),
    ],
  ),
  Song(
    title: '🕊 No Woman No Cry',
    tempo: 78,
    beatsPerChord: 4,
    sections: [
      Section(
        lines: [
          Line(lyric: "[C]No woman no [G]cry, [Am]no woman no [F]cry"),
          Line(lyric: "[C]Said I re[G]member when we used to [Am]sit"),
          Line(lyric: "[F]In the government yard in [C]Trenchtown"),
          Line(lyric: "[G]Observing the [Am]hypocrites as they would [F]mingle with the good people we [C]meet"),
        ],
      ),
      Section(
        name: '🎶 副歌',
        lines: [
          Line(lyric: "[C]Everything's gonna be al[G]right, everything's gonna be al[Am]right"),
          Line(lyric: "[F]Everything's gonna be al[C]right now, [G]everything's gonna be al[C]right"),
        ],
      ),
    ],
  ),
  Song(
    title: '🏔 Country Roads',
    tempo: 82,
    beatsPerChord: 4,
    sections: [
      Section(
        name: '主歌',
        lines: [
          Line(lyric: "[G]Almost heaven, [Em]West Virginia"),
          Line(lyric: "[D]Blue Ridge Mountains, [C]Shenandoah [G]River"),
          Line(lyric: "[G]Life is old there, [Em]older than the trees"),
          Line(lyric: "[D]Younger than the mountains, [C]growin' like a [G]breeze"),
        ],
      ),
      Section(
        name: '🎶 副歌',
        lines: [
          Line(lyric: "[G]Country roads, take me [D]home"),
          Line(lyric: "[Em]To the [C]place I be[G]long"),
          Line(lyric: "[G]West Virginia, [D]mountain mama"),
          Line(lyric: "[C]Take me [G]home, country [D]roads"),
        ],
      ),
    ],
  ),
  Song(
    title: '🎓 那些年',
    tempo: 78,
    beatsPerChord: 4,
    sections: [
      Section(
        name: '主歌',
        lines: [
          Line(lyric: "[C]又回到最初的[G]起点,记忆中你[Am]青涩的[Em]脸"),
          Line(lyric: "[F]我们终于[G]来到了这一[C]天"),
          Line(lyric: "[C]桌垫下的老[G]照片,无数回忆[Am]连[Em]结"),
          Line(lyric: "[F]今天男孩要[G]赴女孩最后[C]的约"),
        ],
      ),
      Section(
        name: '🎶 副歌',
        lines: [
          Line(lyric: "[C]那些年错过[G]的大雨,那些年[Am]错过的爱[Em]情"),
          Line(lyric: "[F]好想拥抱你,[G]拥抱错过的[C]勇气"),
          Line(lyric: "[C]曾经想征服全[G]世界,到最后[Am]回首才发[Em]现"),
          Line(lyric: "[F]这世界滴滴[G]点点全部都[C]是你"),
        ],
      ),
    ],
  ),
  Song(
    title: '🍀 小幸运',
    tempo: 76,
    beatsPerChord: 4,
    sections: [
      Section(
        name: '主歌',
        lines: [
          Line(lyric: "[C]我听见雨滴[G]落在青青[Am]草[F]地"),
          Line(lyric: "[C]我听见远方[G]下课钟声[Am]响[F]起"),
          Line(lyric: "[Am]可是我[F]没有听见[G]你的声音[Em]认真呼唤我[Am]姓名"),
          Line(lyric: "[F]爱上你的[G]时候还不懂[C]感情"),
        ],
      ),
      Section(
        name: '🎶 副歌',
        lines: [
          Line(lyric: "[C]原来你是我[G]最想留住的[Am]幸运,[F]原来我们和爱情[C]曾经靠得[G]那么近"),
          Line(lyric: "[Am]那为我对抗[Em]世界的决[F]定,那陪我[G]淋的雨"),
          Line(lyric: "[F]一幕幕都[G]是你,一尘不[Em]染的[Am]真心"),
          Line(lyric: "[F]与你相遇好[G]幸运,可我已失去[C]为你泪流满面的权利"),
        ],
      ),
    ],
  ),
  Song(
    title: '🍂 遇见',
    tempo: 78,
    beatsPerChord: 3,
    sections: [
      Section(
        name: '主歌',
        lines: [
          Line(lyric: "[C]听见冬天[G]的离开,我[Am]在某年[F]某月醒[G]过来"),
          Line(lyric: "[C]我想我等[G]我期待,未[Am]来却不能[F]因此安[G]排"),
        ],
      ),
      Section(
        name: '🎶 副歌',
        lines: [
          Line(lyric: "[C]阴天傍晚[G]车窗外,未[Am]来有一个[Em]人在等[F]待"),
          Line(lyric: "[C]向左向右[G]向前看,爱[Am]要拐几个[F]弯才[G]来"),
          Line(lyric: "[C]我遇见谁[G]会有怎样的[Am]对白,我[F]等的人[G]他在多远的[C]未来"),
          Line(lyric: "[C]我听见风[G]来自地铁和[Am]人海,我[F]排着队[G]拿着爱的[C]号码牌"),
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
  const FingerpickSlot.rest({int duration = 1})
      : stringIndex = null, fret = 0, duration = duration;
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

  // ═══ 3. Always With Me (千与千寻) ═══
  // 宫崎骏《千与千寻》主题曲,C 调,尤克里里指弹经典入门曲。
  FingerpickSong(
    title: 'Always With Me (千与千寻)',
    subtitle: '宫崎骏 · C 调指弹',
    tempo: 96,
    bars: [
      // 第1小节 C:前奏 空弦拨 G-C-E 建立 C 和弦氛围
      FingerpickBar(lyric: 'C · 前奏', slots: [
        fp(3,3,t:2), fp(2,0,t:2), fp(1,0,t:2), fp(2,0,t:2),
        fp(3,3,t:2), fp(1,0,t:2), fp(0,3,t:2), fpr(t:2),
      ]),
      // 第2小节 G
      FingerpickBar(lyric: 'G', slots: [
        fp(3,2,t:2), fp(2,0,t:2), fp(1,0,t:2), fp(2,0,t:2),
        fp(3,3,t:2), fp(1,0,t:2), fp(0,2,t:2), fpr(t:2),
      ]),
      // 第3小节 Am
      FingerpickBar(lyric: 'Am · 呼んでいる', slots: [
        fp(0,0,t:2), fp(2,0,t:2), fp(1,0,t:2), fp(2,0,t:2),
        fp(0,0,t:2), fp(2,0,t:2), fp(1,2,t:2), fpr(t:2),
      ]),
      // 第4小节 Em
      FingerpickBar(lyric: 'Em · 胸のどこかで', slots: [
        fp(0,2,t:2), fp(2,0,t:2), fp(1,0,t:2), fp(2,0,t:2),
        fp(3,3,t:2), fp(1,0,t:2), fp(0,2,t:2), fpr(t:2),
      ]),
      // 第5小节 F
      FingerpickBar(lyric: 'F · いつも心', slots: [
        fp(0,1,t:2), fp(2,1,t:2), fp(1,1,t:2), fp(2,1,t:2),
        fp(0,1,t:2), fp(2,1,t:2), fp(1,0,t:2), fpr(t:2),
      ]),
      // 第6小节 C
      FingerpickBar(lyric: 'C · 躍る', slots: [
        fp(3,3,t:2), fp(2,0,t:2), fp(1,0,t:2), fp(2,0,t:2),
        fp(3,3,t:2), fp(1,0,t:2), fp(0,3,t:2), fpr(t:2),
      ]),
      // 第7小节 F
      FingerpickBar(lyric: 'F · かなしみは', slots: [
        fp(0,1,t:2), fp(2,1,t:2), fp(1,0,t:2), fp(2,1,t:2),
        fp(3,3,t:2), fp(1,0,t:2), fp(0,1,t:2), fpr(t:2),
      ]),
      // 第8小节 G→收尾:旋律下行 G-F-E-C
      FingerpickBar(lyric: 'G · 数え切れない', slots: [
        fp(0,2,t:2), fp(3,2,t:2), fp(2,0,t:2), fp(1,0,t:2),
        fp(3,3,t:2), fp(2,0,t:2), fp(0,2,t:2), fpr(t:2),
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
// 4321:最经典琶音,一拍一音(四分),一小节正好从低到高滚一遍(G→C→E→A)。
// 4323:伴奏最常用织体,八分音符流动(4-3-2-3 循环)。
const builtinArpPatterns = <ArpPattern>[
  ArpPattern(name: '4321 琶音', strings: [0, 1, 2, 3], notesPerBeat: 1),
  ArpPattern(name: '4323 织体', strings: [0, 1, 2, 1], notesPerBeat: 2),
];

// —— 内置琶音练习(几条最常用和弦进行,都 C/Am 调) ——
// 单和弦慢练放第一个:初学先在一个和弦上把拨弦型练熟,再加换和弦。
const builtinArpStudies = <ArpStudy>[
  ArpStudy(title: '单和弦慢练', subtitle: 'C · 先把右手拨弦练均匀', chords: ['C'], tempo: 70),
  ArpStudy(title: '流行进行', subtitle: '1-5-6-4 · C G Am F · 最常用', chords: ['C', 'G', 'Am', 'F'], tempo: 72),
  ArpStudy(title: '经典进行', subtitle: '1-6-4-5 · C Am F G', chords: ['C', 'Am', 'F', 'G'], tempo: 72),
  ArpStudy(title: '小调色彩', subtitle: '6-4-1-5 · Am F C G', chords: ['Am', 'F', 'C', 'G'], tempo: 72),
];
