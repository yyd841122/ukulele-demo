// 歌曲备份 / 导入(第50步)纯函数的无头测试。
// 锁 encodeBackup / decodeBackup 的「导出 → 导入」往返不丢字段,以及宽松解析 / 错误输入。
// IO(剪贴板 / 分享)由界面层负责,这里只管 Song 列表 ↔ JSON 字符串。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:ukulele_demo/models.dart';
import 'package:ukulele_demo/song_backup.dart';

Song _sample(String title, {String? sectionName, int beats = 4}) => Song(
      id: 'ignored', // 导出会带 id,但导入时 addAll 会重新分配,这里只验编解码
      title: title,
      tempo: 88,
      beatsPerChord: beats,
      sections: [
        Section(
          name: sectionName,
          lines: [Line(lyric: '[C]$title [G]词'), Line(lyric: '[Am]尾')],
        ),
      ],
    );

/// 把歌数组直接拍成裸 JSON 数组文本(测「裸数组也能认」用)。
String _bareArrayJson(List<Song> songs) =>
    jsonEncode([for (final s in songs) s.toJson()]);

void main() {
  group('encodeBackup / decodeBackup 往返', () {
    test('导出 → 导入:字段不丢(标题 / 拍数 / 段名 / 行内和弦)', () {
      final songs = [_sample('歌一'), _sample('歌二', sectionName: '副歌', beats: 3)];
      final backup = encodeBackup(songs);

      final back = decodeBackup(backup);
      expect(back.length, 2);
      expect(back[0].title, '歌一');
      expect(back[0].beatsPerChord, 4);
      expect(back[1].title, '歌二');
      expect(back[1].beatsPerChord, 3);
      expect(back[1].sections.first.name, '副歌');
      expect(back[1].sections.first.lines.first.chords, ['C', 'G']);
    });

    test('导出结果带壳:app / kind / version / songs 字段都在,且是合法 JSON', () {
      final backup = encodeBackup([_sample('只此一首')]);
      final shell = jsonDecode(backup) as Map<String, dynamic>;
      expect(shell['app'], 'ukulele-demo');
      expect(shell['kind'], 'song-backup');
      expect(shell['version'], kBackupVersion);
      expect((shell['songs'] as List).length, 1);
    });

    test('空列表也合法:导出空、导回空(不崩)', () {
      final backup = encodeBackup([]);
      expect(decodeBackup(backup), isEmpty);
    });

    test('确定性:同样的歌两次导出完全相同(无时间戳 / 随机)', () {
      final s = [_sample('x')];
      expect(encodeBackup(s), encodeBackup(s));
    });
  });

  group('decodeBackup 宽松解析', () {
    test('也认光秃秃的数组(没壳):[ {...}, {...} ]', () {
      final bare = _bareArrayJson([_sample('a'), _sample('b')]);
      final back = decodeBackup(bare);
      expect(back.length, 2);
      expect(back[0].title, 'a');
      expect(back[1].title, 'b');
    });

    test('前后空白能容忍(自动 trim)', () {
      final backup = encodeBackup([_sample('c')]);
      final back = decodeBackup('  \n$backup\n  ');
      expect(back.length, 1);
      expect(back.first.title, 'c');
    });
  });

  group('decodeBackup 错误输入', () {
    test('不是 JSON → FormatException', () {
      expect(() => decodeBackup('根本不是 json'), throwsFormatException);
    });

    test('是 JSON 但没有 songs 字段 → FormatException', () {
      expect(() => decodeBackup('{"foo": 1}'), throwsFormatException);
    });

    test('是 JSON 但 songs 不是数组 → FormatException', () {
      expect(() => decodeBackup('{"songs": "nope"}'), throwsFormatException);
    });
  });
}
