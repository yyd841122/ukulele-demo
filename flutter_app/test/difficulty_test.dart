// 难度推导(完善Step4):从歌词里的和弦标记算歌曲难度 + 提取用了哪些和弦。纯函数、无头可测。
//
// 难度不写死在每首歌上、而是从【用了哪些和弦】算出来——和弦改了难度自动跟上,
// 用户自加的歌也自动有难度标签。规则见 difficultyOf 注释。
import 'package:flutter_test/flutter_test.dart';
import 'package:ukulele_demo/models.dart';

void main() {
  group('chordsOf', () {
    test('提取歌词里的合法和弦、去重', () {
      final s = Song(
        title: 't',
        tempo: 80,
        sections: [
          Section(lines: [Line(lyric: '[C]词 [G]词 [C]再 [F]尾')]),
        ],
      );
      expect(chordsOf(s), {'C', 'G', 'F'});
    });

    test('忽略不是和弦的方括号标记(只认 chordShapes 里的)', () {
      final s = Song(
        title: 't',
        tempo: 80,
        sections: [Section(lines: [Line(lyric: '[C]词 [瞎写]不合法')])],
      );
      expect(chordsOf(s), {'C'});
    });

    test('跨段跨行合并去重', () {
      final s = Song(
        title: 't',
        tempo: 80,
        sections: [
          Section(name: '主歌', lines: [Line(lyric: '[C]a [G]b'), Line(lyric: '[Am]c')]),
          Section(name: '副歌', lines: [Line(lyric: '[F]d [C]e')]),
        ],
      );
      expect(chordsOf(s), {'C', 'G', 'Am', 'F'});
    });
  });

  group('difficultyOf', () {
    Song song(String lyric) => Song(
      title: 't',
      tempo: 80,
      sections: [Section(lines: [Line(lyric: lyric)])],
    );

    test('≤3 个最基本和弦(无 F/7)→ 入门(1)', () {
      expect(difficultyOf(song('[C]a [G]b')), 1); // 2 和弦
      expect(difficultyOf(song('[Am]a [C]b [G]c')), 1); // 3 和弦、无 F/7(像 Riptide)
    });
    test('含 F → 初级(2)(F 是第一道坎,踢出入门)', () {
      expect(difficultyOf(song('[C]a [G]b [F]c')), 2);
    });
    test('4 和弦 → 初级(2)', () {
      expect(difficultyOf(song('[C]a [G]b [F]c [D]d')), 2);
    });
    test('5 个及以上和弦 → 进阶(3)', () {
      expect(difficultyOf(song('[C]a [G]b [F]c [D]d [Am]e')), 3);
    });

    test('内置歌三档都对(Rainbow=初级 / You Are My Sunshine=入门 / 童话=进阶)', () {
      Song byTitle(String t) => builtinSongs.firstWhere((s) => s.title.contains(t));
      expect(difficultyOf(byTitle('Over the Rainbow')), 2); // Am C F G(含 F、4 和弦)
      expect(difficultyOf(byTitle('You Are My Sunshine')), 1); // C G(2 和弦、无 F/7)
      expect(difficultyOf(byTitle('童话')), 3); // 7 和弦(5+)
    });
  });

  test('difficultyLabel:1=入门 / 2=初级 / 3=进阶 / 其它回退初级', () {
    expect(difficultyLabel(1), '入门');
    expect(difficultyLabel(2), '初级');
    expect(difficultyLabel(3), '进阶');
    expect(difficultyLabel(9), '初级');
  });
}
