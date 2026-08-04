// 持久化用户偏好:跨 app 重启记住"上次练到哪、调到多快、用什么节奏型、设了哪段 AB"。
//
// 包一层 SharedPreferences:对外只给"读/写某项偏好"的方法,把 key 字符串和 getInt/setInt 这些
// 细节藏起来。SongScreen 只调它的方法、不直接碰 SharedPreferences。
//
// 速度和 AB 都是【按歌存】的(key 带歌曲下标)——它们只对某首歌有意义,换歌不能串。
// 歌曲下标、节奏型是全局的(节奏型本来就是跨歌保留的练习偏好)。
import 'package:shared_preferences/shared_preferences.dart';

class AppPreferences {
  final SharedPreferences _prefs;
  AppPreferences(this._prefs);

  /// 异步加载一次(SongScreen 在 initState 里调,加载完再 reconcile 状态)。
  static Future<AppPreferences> load() async =>
      AppPreferences(await SharedPreferences.getInstance());

  // —— 全局偏好 ——
  // 上次选的歌在 songs 列表里的下标。
  int getSongIndex(int fallback) => _prefs.getInt(_kSongIndex) ?? fallback;
  Future<void> setSongIndex(int i) => _prefs.setInt(_kSongIndex, i);

  // 当前选的扫弦节奏型(patternsFor 返回那几个里的第几个)。跨歌保留。
  int getPatternIndex(int fallback) =>
      _prefs.getInt(_kPatternIndex) ?? fallback;
  Future<void> setPatternIndex(int i) => _prefs.setInt(_kPatternIndex, i);

  // 扫弦声开关(播放时按节奏型播真扫弦声 vs 只敲节拍器嗒声)。跨歌保留的练习偏好。
  bool getStrumSound([bool fallback = true]) =>
      _prefs.getBool(_kStrumSound) ?? fallback;
  Future<void> setStrumSound(bool v) => _prefs.setBool(_kStrumSound, v);

  // —— 按歌存的偏好(key 带歌曲下标)——
  // 某首歌上次调到的速度(BPM);没存过返回 null → 用原速。
  int? getTempo(int songIndex) => _prefs.getInt('$_kTempoPrefix$songIndex');
  Future<void> setTempo(int songIndex, int v) =>
      _prefs.setInt('$_kTempoPrefix$songIndex', v);

  // 某首歌设的 AB 循环区间(起止行下标)。两个都 null = 没设。a、b 任一 null 视为不完整。
  ({int? a, int? b})? getAb(int songIndex) {
    final a = _prefs.getInt('$_kAbAPrefix$songIndex');
    final b = _prefs.getInt('$_kAbBPrefix$songIndex');
    if (a == null && b == null) return null; // 都没存 = 从没设过
    return (a: a, b: b);
  }

  /// 存某首歌的 AB 区间。传 null 表示清除那一头(整段清除就两个都传 null)。
  Future<void> setAb(int songIndex, int? a, int? b) async {
    final keyA = '$_kAbAPrefix$songIndex';
    final keyB = '$_kAbBPrefix$songIndex';
    if (a == null) {
      await _prefs.remove(keyA);
    } else {
      await _prefs.setInt(keyA, a);
    }
    if (b == null) {
      await _prefs.remove(keyB);
    } else {
      await _prefs.setInt(keyB, b);
    }
  }

  // —— 练琴打卡(按歌存)——
  // 累计遍数:这首歌跨会话总共完整练了多少遍(_loops 只算本次会话,换歌清零;这个是持久累计)。
  int getLoops(int songIndex) => _prefs.getInt('$_kLoopsPrefix$songIndex') ?? 0;
  Future<void> setLoops(int songIndex, int n) =>
      _prefs.setInt('$_kLoopsPrefix$songIndex', n);

  // 累计练习秒数:这首歌总共练了多少秒(只在播放中计时,暂停/换歌/退出时结算)。
  int getSec(int songIndex) => _prefs.getInt('$_kSecPrefix$songIndex') ?? 0;
  Future<void> setSec(int songIndex, int n) =>
      _prefs.setInt('$_kSecPrefix$songIndex', n);

  // key 常量:集中放一处,免得读写各处拼字符串拼错。
  static const _kSongIndex = 'pref_song_index';
  static const _kPatternIndex = 'pref_pattern_index';
  static const _kStrumSound = 'pref_strum_sound';
  static const _kTempoPrefix = 'pref_tempo_'; // 后接歌曲下标,如 pref_tempo_2
  static const _kAbAPrefix = 'pref_ab_a_'; // 后接歌曲下标
  static const _kAbBPrefix = 'pref_ab_b_';
  static const _kLoopsPrefix = 'pref_loops_'; // 后接歌曲下标
  static const _kSecPrefix = 'pref_sec_'; // 后接歌曲下标
}
