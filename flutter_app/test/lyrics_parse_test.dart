// 第46步:歌词文本 → 段落(parseLyrics)的无头测试。锁 #名字 段落命名 + 空行分段 + 行内和弦照常解析。
import 'package:flutter_test/flutter_test.dart';

import 'package:ukulele_demo/models.dart';

void main() {
  test('空文本 → 没有段落', () {
    expect(parseLyrics(''), isEmpty);
  });

  test('纯歌词(没 #名字、没空行)= 单个匿名段,行内和弦照常解析', () {
    final s = parseLyrics('[C]词1\n词2');
    expect(s.length, 1);
    expect(s.first.name, isNull);
    expect(s.first.lines.length, 2);
    expect(s.first.lines.first.chords, ['C']);
  });

  test('空行分段 = 多个匿名段', () {
    final s = parseLyrics('[C]词1\n\n[Am]词2');
    expect(s.length, 2);
    expect(s[0].name, isNull);
    expect(s[1].name, isNull);
    expect(s[0].lines.first.lyric, '[C]词1');
    expect(s[1].lines.first.lyric, '[Am]词2');
  });

  test('#名字 给段落命名(这行本身不是歌词)', () {
    final s = parseLyrics('#主歌\n[C]词1\n\n#副歌\n[F]高潮');
    expect(s.length, 2);
    expect(s[0].name, '主歌');
    expect(s[0].lines.length, 1);
    expect(s[1].name, '副歌');
    expect(s[1].lines.first.lyric, '[F]高潮');
  });

  test('名字后没歌词 → 那个空段被丢掉(不造没词的段)', () {
    final s = parseLyrics('[C]词1\n#副歌');
    expect(s.length, 1); // '副歌' 后面没词,不单列一段
    expect(s.first.name, isNull);
  });

  test('# 后面空白 → 当匿名段(不造空名字)', () {
    final s = parseLyrics('#\n[C]词1');
    expect(s.length, 1);
    expect(s.first.name, isNull); // 空 # 归一成匿名
  });
}
