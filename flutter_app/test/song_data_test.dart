// 内置歌数据合法性守卫(第15步加):
// 扫描每首内置歌每行解析出来的所有和弦,断言都在 chordShapes 里——
// 不在的话画和弦图会崩、playString 会静音,是加歌最容易踩的坑(和弦名拼错 / 大小写 / 脏字符)。
// 再守 beatsPerChord ∈ 支持集合、段落/行结构非空。
import 'package:flutter_test/flutter_test.dart';
import 'package:ukulele_demo/models.dart';

void main() {
  group('内置歌数据合法性', () {
    test('每首歌的每个和弦都在 chordShapes 里(画图 + playString 都依赖)', () {
      for (final song in builtinSongs) {
        final allChords = <String>{};
        for (final sec in song.sections) {
          for (final line in sec.lines) {
            allChords.addAll(line.chords);
          }
        }
        expect(allChords.isNotEmpty, true, reason: '「${song.title}」没有任何和弦标记');
        for (final c in allChords) {
          expect(chordShapes.containsKey(c), true,
              reason: '「${song.title}」的和弦「$c」不在 chordShapes 里 → 画图崩 / playString 静音');
        }
      }
    });

    test('每首歌 beatsPerChord ∈ {2,3,4,6,8}(add_song 支持集合)', () {
      for (final song in builtinSongs) {
        expect(song.beatsPerChord, isIn([2, 3, 4, 6, 8]),
            reason: '「${song.title}」beatsPerChord=${song.beatsPerChord} 不在支持集合');
      }
    });

    test('每首歌至少 1 个段落、每段至少 1 行(空歌会让练习页崩)', () {
      for (final song in builtinSongs) {
        expect(song.sections.isNotEmpty, true, reason: '「${song.title}」没有段落');
        for (final sec in song.sections) {
          expect(sec.lines.isNotEmpty, true,
              reason: '「${song.title}」的段落「${sec.name ?? '(匿名)'}」没有歌词行');
        }
      }
    });

    test('歌名不重复(下拉框按 title 认歌,重复会混淆)', () {
      final titles = builtinSongs.map((s) => s.title).toList();
      expect(titles.toSet().length, titles.length,
          reason: '有重复歌名:${titles.where((t) => titles.where((x) => x == t).length > 1).toSet()}');
    });
  });

  group('PD 扫弦歌 4 首(第15步)', () {
    // 锁住这 4 首的关键不变量:存在、拍数、用到的小和弦集——
    // 以后误删/误改这 4 首会立刻红,也让"它们确实在内置库里"可被无头验证。
    test('4 首都在内置库里、拍数正确', () {
      bool has(String sub) => builtinSongs.any((s) => s.title.contains(sub));
      expect(has('送别'), true);
      expect(has('奇异恩典'), true);
      expect(has('友谊地久天长'), true);
      expect(has('茉莉花'), true);

      final ag = builtinSongs.firstWhere((s) => s.title.contains('奇异恩典'));
      expect(ag.beatsPerChord, 3, reason: '奇异恩典是 3/4 华尔兹');
      final sb = builtinSongs.firstWhere((s) => s.title.contains('送别'));
      expect(sb.beatsPerChord, 4);
    });
  });
}
