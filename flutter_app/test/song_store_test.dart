// 第43b 步:Song 序列化(用户歌持久化)+ 歌库(SongStore)的无头测试。
// 不连手机(flutter test):验证"toJson/fromJson 来回不丢字段"、"加一首用户歌能存、重启读回 id 不变"。
// shared_preferences 在 flutter_test 自动 mock;setMockInitialValues 给每个测试干净起点。
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ukulele_demo/models.dart';
import 'package:ukulele_demo/prefs/app_preferences.dart';
import 'package:ukulele_demo/song_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Song JSON', () {
    test('toJson → fromJson 来回:字段不丢(含段落名 / 行内和弦)', () {
      final s = Song(
        id: 'u1',
        title: '我的歌',
        tempo: 88,
        beatsPerChord: 4,
        sections: [
          Section(
            name: '副歌',
            lines: [Line(lyric: '[C]词 [G]词'), Line(lyric: '[Am]尾')],
          ),
        ],
      );
      final back = Song.fromJson(s.toJson());
      expect(back.id, 'u1');
      expect(back.title, '我的歌');
      expect(back.tempo, 88);
      expect(back.beatsPerChord, 4);
      expect(back.sections.length, 1);
      expect(back.sections.first.name, '副歌');
      expect(back.sections.first.lines.length, 2);
      expect(back.sections.first.lines.first.lyric, '[C]词 [G]词');
      // 行内和弦解析没坏
      expect(back.sections.first.lines.first.chords, ['C', 'G']);
    });

    test('fromJson:字段缺失给默认值(防旧版存的歌缺新字段挂掉)', () {
      final back = Song.fromJson({});
      expect(back.id, '');
      expect(back.title, '(未命名)');
      expect(back.tempo, 80);
      expect(back.beatsPerChord, 4);
      expect(back.sections, isEmpty);
    });
  });

  group('SongStore', () {
    test('构造时内置歌就位(界面第一帧有歌),用户歌为空', () {
      final store = SongStore();
      expect(store.songs.length, builtinSongs.length);
      // 内置歌都补了 id(下标字符串),不是空
      expect(store.songs.first.id, '0');
      expect(store.songs.last.id, '${builtinSongs.length - 1}');
    });

    test('加一首用户歌 → 持久化 → 重启读回(id 跨重启稳定)', () async {
      var p = await AppPreferences.load();
      final store = SongStore();
      await store.load(p);
      final builtinCount = store.songs.length;
      expect(store.isUserSong(store.songs.first), isFalse); // 内置歌不是用户歌

      final created = store.add(Song(
        title: '我的歌',
        tempo: 90,
        sections: [Section(lines: [Line(lyric: '[C]词')])],
      ));
      expect(created.id, 'u1'); // 第一首用户歌 = u1
      expect(store.songs.length, builtinCount + 1);
      expect(store.isUserSong(created), isTrue);
      expect(store.songs.last.title, '我的歌');

      // 模拟重启:新歌库、同一份 prefs,用户歌该读回、id 不变。
      p = await AppPreferences.load();
      final store2 = SongStore();
      await store2.load(p);
      expect(store2.songs.length, builtinCount + 1);
      expect(store2.songs.last.id, 'u1');
      expect(store2.songs.last.title, '我的歌');
      expect(store2.songs.last.tempo, 90);
    });

    test('改一首用户歌:update 后内容变、id 不变、持久化', () async {
      var p = await AppPreferences.load();
      final store = SongStore();
      await store.load(p);
      final created = store.add(Song(
        title: '旧标题',
        tempo: 90,
        sections: [Section(lines: [Line(lyric: '[C]词')])],
      ));
      store.update(Song(
        id: created.id,
        title: '新标题',
        tempo: 120,
        sections: [Section(lines: [Line(lyric: '[G]新词')])],
      ));
      expect(store.songs.last.id, created.id); // id 不变
      expect(store.songs.last.title, '新标题');
      expect(store.songs.last.tempo, 120);

      // 重启:改完持久化了
      p = await AppPreferences.load();
      final store2 = SongStore();
      await store2.load(p);
      expect(store2.songs.last.title, '新标题');
      expect(store2.songs.last.tempo, 120);
    });

    test('删一首用户歌:移除 + 持久化(重启也没了)', () async {
      var p = await AppPreferences.load();
      final store = SongStore();
      await store.load(p);
      final builtinCount = store.songs.length;
      final created = store.add(Song(
        title: '删我',
        tempo: 90,
        sections: [Section(lines: [Line(lyric: '[C]词')])],
      ));

      store.remove(created.id);
      expect(store.songs.length, builtinCount); // 列表立刻少一首

      // 重启:这首歌没了(fire-and-forget 的持久化在这步 await 落盘)。
      // remove 顺带清偏好的效果(clearSong)在 prefs_test 里单独、确定性测。
      p = await AppPreferences.load();
      final store2 = SongStore();
      await store2.load(p);
      expect(store2.songs.length, builtinCount);
      expect(store2.songs.where((s) => s.id == created.id), isEmpty);
    });
  });
}
