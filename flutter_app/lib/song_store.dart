// 歌曲库(第43b步):统一拥有【内置歌 + 用户自加歌】的合并列表,管用户歌的持久化 + 通知界面刷新。
//
// 为什么需要它:之前界面直接读顶层 const songs。要让用户加 / 删歌就得有个【可变】歌源,而且加 / 删后
// 练习页(选歌下拉框)、统计页(按歌列表)都得跟着刷新——所以它 extends ChangeNotifier:
// 界面 addListener,歌单一变 notifyListeners,界面就重建。
//
// 内置歌的 id = 下标字符串('0'、'1'…),跟旧版按下标存的偏好键一致 → 旧数据零迁移(见 models.dart)。
// 用户歌 id = 'u1'、'u2'……(getUserSongSeq 计数,删了不复用)。内置歌 id 不以 'u' 开头,泾渭分明。
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'models.dart';
import 'prefs/app_preferences.dart';

class SongStore extends ChangeNotifier {
  // 合并后的歌单。构造时就放好内置歌(补 id),界面第一帧就有歌可显、无需加载挡板;用户歌 load() 后追加。
  List<Song> _songs = [
    for (var i = 0; i < builtinSongs.length; i++) builtinSongs[i].copyWith(id: '$i'),
  ];
  List<Song> get songs => _songs;

  AppPreferences? _prefs;
  int _userSeq = 0; // 用户歌 id 计数(分配 'u1'、'u2'……用)

  /// 加载用户歌(读 prefs JSON)、追加到内置歌后面。MainScaffold 启动时调一次。
  Future<void> load(AppPreferences p) async {
    _prefs = p;
    _userSeq = p.getUserSongSeq();
    final userSongs = [
      for (final j in p.getUserSongs())
        Song.fromJson(jsonDecode(j) as Map<String, dynamic>),
    ];
    if (userSongs.isEmpty) return; // 没用户歌:不动 _songs(免得无谓 notify、白刷一帧)
    _songs = [..._songs, ...userSongs];
    notifyListeners();
  }

  /// 这首歌是用户自加的吗?(用户歌 id 以 'u' 开头;内置歌是数字 id)。加 / 删 / 改只对用户歌开放。
  bool isUserSong(Song s) => s.id.startsWith('u');

  /// 加一首用户歌:分配新 id(u1、u2……)、追加、持久化、通知。返回带 id 的新歌。
  Song add(Song song) {
    final p = _prefs;
    if (p == null) return song; // 没加载完不该走到这(界面入口在 store load 后才可用)
    _userSeq++;
    final withId = song.copyWith(id: 'u$_userSeq');
    p.setUserSongSeq(_userSeq);
    _songs = [..._songs, withId];
    _persist(p);
    notifyListeners();
    return withId;
  }

  /// 把当前所有用户歌写回 prefs(每首一条 JSON 字符串)。内置歌不写(它们在代码里)。
  void _persist(AppPreferences p) {
    final jsons = [for (final s in _songs.where(isUserSong)) jsonEncode(s.toJson())];
    p.setUserSongs(jsons);
  }
}
