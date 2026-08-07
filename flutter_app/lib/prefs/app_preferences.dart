// 持久化用户偏好:跨 app 重启记住"上次练到哪、调到多快、用什么节奏型、设了哪段 AB"。
//
// 包一层 SharedPreferences:对外只给"读/写某项偏好"的方法,把 key 字符串和 getInt/setInt 这些
// 细节藏起来。SongScreen 只调它的方法、不直接碰 SharedPreferences。
//
// 速度和 AB 都是【按歌存】的(key 带歌曲下标)——它们只对某首歌有意义,换歌不能串。
// 歌曲下标、节奏型是全局的(节奏型本来就是跨歌保留的练习偏好)。
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart'; // practiceDayKey:把 DateTime 折成 'yyyy-MM-dd' 当字典 key

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

  // 自动提速开关(每过一遍 +3 BPM、到原速停的渐进提速练法)。跨歌保留的练习偏好。
  bool getRamp([bool fallback = false]) =>
      _prefs.getBool(_kRamp) ?? fallback;
  Future<void> setRamp(bool v) => _prefs.setBool(_kRamp, v);

  // 歌词字号缩放(1.0 = 默认大小;>1 放大、<1 缩小)。全局偏好——一个人看歌词的习惯跟哪首歌无关。
  // 调用方负责 clamp 到合理区间(界面 Slider 限定 0.8~1.8);这里只管原样存/读,跟 tempo 一个套路。
  double getLyricScale([double fallback = 1.0]) =>
      _prefs.getDouble(_kLyricScale) ?? fallback;
  Future<void> setLyricScale(double v) => _prefs.setDouble(_kLyricScale, v);

  // A4 校准(调音器"准"的基准频率)。全局偏好——一个人的调音基准跟哪首歌无关。
  // 默认 440(标准音高);调交响音高(442 等)时调高。界面 Slider 限定 430~450。
  double getA4([double fallback = 440]) => _prefs.getDouble(_kA4) ?? fallback;
  Future<void> setA4(double v) => _prefs.setDouble(_kA4, v);

  // —— 换和弦训练(全局;上次选的两个和弦 / 速度 / 每几拍换 / 60 秒挑战开关)——
  // 不按歌存——它跟具体哪首歌无关,是独立的切换练习。存了就记住上次选的,跨 app 重启还在;
  // 没存过调用方给默认(C↔G / 60 BPM / 4 拍 / 挑战关)。和弦名存字符串,调用方负责校验还在 chordShapes 里。
  String getTrainerChordA(String fallback) =>
      _prefs.getString(_kTrainerChordA) ?? fallback;
  Future<void> setTrainerChordA(String v) =>
      _prefs.setString(_kTrainerChordA, v);

  String getTrainerChordB(String fallback) =>
      _prefs.getString(_kTrainerChordB) ?? fallback;
  Future<void> setTrainerChordB(String v) =>
      _prefs.setString(_kTrainerChordB, v);

  int getTrainerBpm(int fallback) => _prefs.getInt(_kTrainerBpm) ?? fallback;
  Future<void> setTrainerBpm(int v) => _prefs.setInt(_kTrainerBpm, v);

  int getTrainerBeats(int fallback) =>
      _prefs.getInt(_kTrainerBeats) ?? fallback;
  Future<void> setTrainerBeats(int v) => _prefs.setInt(_kTrainerBeats, v);

  bool getTrainerChallenge([bool fallback = false]) =>
      _prefs.getBool(_kTrainerChallenge) ?? fallback;
  Future<void> setTrainerChallenge(bool v) =>
      _prefs.setBool(_kTrainerChallenge, v);

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

  // —— 练习日历(哪天练过,跨歌汇总)——
  // 存 practiceDayKey 字符串('yyyy-MM-dd')列表、去重。给统计页画日历热力图 + 算"连续打卡 N 天"。
  // 跨歌(不按歌存):练了哪天跟哪首歌无关,日历看的是"有没有练"。SongScreen 在真正攒到练习秒数时标记。
  List<String> getPracticeDays() =>
      _prefs.getStringList(_kPracticeDays) ?? [];
  /// 标记今天练过(去重:已记过就 no-op)。SongScreen._accumulateSec 攒到 >=1 秒时调。
  Future<void> markPracticedToday() async {
    final today = practiceDayKey(DateTime.now());
    final days = getPracticeDays();
    if (days.contains(today)) return; // 今天已记过,不重复加
    days.add(today);
    await _prefs.setStringList(_kPracticeDays, days);
  }

  // key 常量:集中放一处,免得读写各处拼字符串拼错。
  static const _kSongIndex = 'pref_song_index';
  static const _kPatternIndex = 'pref_pattern_index';
  static const _kStrumSound = 'pref_strum_sound';
  static const _kRamp = 'pref_ramp';
  static const _kLyricScale = 'pref_lyric_scale';
  static const _kA4 = 'pref_a4'; // 调音器 A4 校准基准(Hz)
  static const _kTrainerChordA = 'pref_trainer_chord_a'; // 换和弦训练:上次选的和弦 A
  static const _kTrainerChordB = 'pref_trainer_chord_b'; // 换和弦训练:上次选的和弦 B
  static const _kTrainerBpm = 'pref_trainer_bpm'; // 换和弦训练:速度
  static const _kTrainerBeats = 'pref_trainer_beats'; // 换和弦训练:每几拍换
  static const _kTrainerChallenge = 'pref_trainer_challenge'; // 换和弦训练:60 秒挑战开关
  static const _kTempoPrefix = 'pref_tempo_'; // 后接歌曲下标,如 pref_tempo_2
  static const _kAbAPrefix = 'pref_ab_a_'; // 后接歌曲下标
  static const _kAbBPrefix = 'pref_ab_b_';
  static const _kLoopsPrefix = 'pref_loops_'; // 后接歌曲下标
  static const _kSecPrefix = 'pref_sec_'; // 后接歌曲下标
  static const _kPracticeDays = 'pref_practice_days'; // 'yyyy-MM-dd' 字符串列表
}
