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
  // 上次选的歌的【id】(第45步起:从按下标改成按 id 存)。原因:用户加 / 删歌会让下标挪位,
  // 按下标存的"上次选哪首"重启后可能恢复到别的歌;按 id 存不会。内置歌 id = 下标字符串,
  // 所以旧版按下标存的值一次性迁移过来就行(迁移在 song_screen._loadPrefs 里做)。
  String? getSelectedSongId() => _prefs.getString(_kSelectedSongId);
  Future<void> setSelectedSongId(String id) =>
      _prefs.setString(_kSelectedSongId, id);

  // 旧版(第45步前)按下标存的"上次选歌下标"。只留来一次性迁移读;迁移完不再写、成孤儿 key(无害)。
  int getLegacySongIndex(int fallback) => _prefs.getInt(_kSongIndex) ?? fallback;

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

  // 主题模式(第47步):'system' / 'light' / 'dark'。默认 system(跟手机系统);统计页能手动切、跨重启记得住。
  String getThemeMode([String fallback = 'system']) =>
      _prefs.getString(_kThemeMode) ?? fallback;
  Future<void> setThemeMode(String mode) => _prefs.setString(_kThemeMode, mode);

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

  // —— 用户自加的歌(第43b起)——
  // 存成一串 JSON 字符串(每首一首);启动时 SongStore 读出来、跟内置歌合并。id 存在 JSON 里,跨重启稳定。
  List<String> getUserSongs() => _prefs.getStringList(_kUserSongs) ?? [];
  Future<void> setUserSongs(List<String> jsons) =>
      _prefs.setStringList(_kUserSongs, jsons);

  // 用户歌 id 计数器:每加一首 +1 → 'u1'、'u2'……不重复;删了不复用(免得新歌顶到旧歌的残留记录)。
  int getUserSongSeq([int fallback = 0]) =>
      _prefs.getInt(_kUserSongSeq) ?? fallback;
  Future<void> setUserSongSeq(int n) => _prefs.setInt(_kUserSongSeq, n);

  // —— 按歌存的偏好(key 带歌曲 id)——
  // 第43a步:从"按下标 songIndex"改成"按 id songId"。内置歌的 id = 下标字符串('0'、'1'…),
  // 所以键(pref_tempo_0 等)跟旧版完全一致 → 旧练习数据零迁移、原样读得到。用户歌用 'u1'、'u2' 这种 id。
  // 某首歌上次调到的速度(BPM);没存过返回 null → 用原速。
  int? getTempo(String songId) => _prefs.getInt('$_kTempoPrefix$songId');
  Future<void> setTempo(String songId, int v) =>
      _prefs.setInt('$_kTempoPrefix$songId', v);

  // 某首歌的移调(虚拟变调夹,半音偏移)。没存过返回 0(不移调 = 原音高)。按歌存——每首歌贴合
  // 嗓音要的移调不一样,跟 tempo 一个套路;切歌不串。范围由界面 Slider 限定(-6~+6)。
  int getTranspose(String songId) =>
      _prefs.getInt('$_kTransposePrefix$songId') ?? 0;
  Future<void> setTranspose(String songId, int v) =>
      _prefs.setInt('$_kTransposePrefix$songId', v);

  // 某首歌设的 AB 循环区间(起止行下标)。两个都 null = 没设。a、b 任一 null 视为不完整。
  ({int? a, int? b})? getAb(String songId) {
    final a = _prefs.getInt('$_kAbAPrefix$songId');
    final b = _prefs.getInt('$_kAbBPrefix$songId');
    if (a == null && b == null) return null; // 都没存 = 从没设过
    return (a: a, b: b);
  }

  /// 存某首歌的 AB 区间。传 null 表示清除那一头(整段清除就两个都传 null)。
  Future<void> setAb(String songId, int? a, int? b) async {
    final keyA = '$_kAbAPrefix$songId';
    final keyB = '$_kAbBPrefix$songId';
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
  int getLoops(String songId) => _prefs.getInt('$_kLoopsPrefix$songId') ?? 0;
  Future<void> setLoops(String songId, int n) =>
      _prefs.setInt('$_kLoopsPrefix$songId', n);

  // 累计练习秒数:这首歌总共练了多少秒(只在播放中计时,暂停/换歌/退出时结算)。
  int getSec(String songId) => _prefs.getInt('$_kSecPrefix$songId') ?? 0;
  Future<void> setSec(String songId, int n) =>
      _prefs.setInt('$_kSecPrefix$songId', n);

  /// 清掉某首歌的所有偏好(删用户歌时调,免得留垃圾 key)。内置歌不走这(不可删)。
  Future<void> clearSong(String id) async {
    await _prefs.remove('$_kTempoPrefix$id');
    await _prefs.remove('$_kTransposePrefix$id');
    await _prefs.remove('$_kAbAPrefix$id');
    await _prefs.remove('$_kAbBPrefix$id');
    await _prefs.remove('$_kLoopsPrefix$id');
    await _prefs.remove('$_kSecPrefix$id');
    await _prefs.remove('$_kLastPracticedPrefix$id');
  }

  // —— 上次练习日期(按歌存,第55步)——
  // 存 ISO 日期字符串 'yyyy-MM-dd';读的时候折回 DateTime。没存过返回 null。
  String? getLastPracticed(String songId) =>
      _prefs.getString('$_kLastPracticedPrefix$songId');
  Future<void> setLastPracticed(String songId, String isoDate) =>
      _prefs.setString('$_kLastPracticedPrefix$songId', isoDate);

  // —— 练习日历(哪天练过,跨歌汇总)——
  // 存 practiceDayKey 字符串('yyyy-MM-dd')列表、去重。给统计页画日历热力图 + 算"连续打卡 N 天"。
  // 跨歌(不按歌存):练了哪天跟哪首歌无关,日历看的是"有没有练"。SongScreen 在真正攒到练习秒数时标记。
  List<String> getPracticeDays() =>
      _prefs.getStringList(_kPracticeDays) ?? [];
  /// 标记今天练过(去重:已记过就 no-op)。SongScreen._accumulateSec 攒到 >=1 秒时调。
  Future<void> markPracticedToday() async {
    final today = practiceDayKey(DateTime.now());
    final days = [...getPracticeDays()]; // 先复制:SharedPreferences 有些实现返回不可变列表
    if (days.contains(today)) return; // 今天已记过,不重复加
    days.add(today);
    await _prefs.setStringList(_kPracticeDays, days);
  }

  // —— 收藏歌曲(第58步-2)——
  Set<String> getFavorites() =>
      (_prefs.getStringList(_kFavorites) ?? []).toSet();
  Future<void> setFavorites(List<String> ids) =>
      _prefs.setStringList(_kFavorites, ids);

  // —— 每日练习目标(第58步-3)——
  int getDailyGoalMin([int fallback = 30]) =>
      _prefs.getInt(_kDailyGoalMin) ?? fallback;
  Future<void> setDailyGoalMin(int v) =>
      _prefs.setInt(_kDailyGoalMin, v);

  /// 今天的练琴秒数(第58步-3)。[todayDate] = 今天的日期键(yyyy-MM-dd);
  /// 如果存的日期跟 [todayDate] 不一致就说明跨天了,归零重计。
  int getTodaySec(String todayDate) {
    final storedDate = _prefs.getString(_kTodaySecDate);
    if (storedDate != todayDate) return 0;
    return _prefs.getInt(_kTodaySec) ?? 0;
  }

  Future<void> setTodaySec(String todayDate, int sec) async {
    await _prefs.setString(_kTodaySecDate, todayDate);
    await _prefs.setInt(_kTodaySec, sec);
  }

  // —— 练习提醒(第58步-4)——
  bool getReminderEnabled([bool fallback = false]) =>
      _prefs.getBool(_kReminderEnabled) ?? fallback;
  Future<void> setReminderEnabled(bool v) =>
      _prefs.setBool(_kReminderEnabled, v);

  int getReminderHour([int fallback = 19]) =>
      _prefs.getInt(_kReminderHour) ?? fallback;
  Future<void> setReminderHour(int v) =>
      _prefs.setInt(_kReminderHour, v);

  int getReminderMinute([int fallback = 0]) =>
      _prefs.getInt(_kReminderMinute) ?? fallback;
  Future<void> setReminderMinute(int v) =>
      _prefs.setInt(_kReminderMinute, v);

  // —— 节拍器声音(第58步-5)——
  String getMetronomeSound([String fallback = 'click']) =>
      _prefs.getString(_kMetronomeSound) ?? fallback;
  Future<void> setMetronomeSound(String v) =>
      _prefs.setString(_kMetronomeSound, v);

  // —— 换和弦训练增强(第58步-7)——
  String getTrainerDifficulty([String fallback = 'custom']) =>
      _prefs.getString(_kTrainerDifficulty) ?? fallback;
  Future<void> setTrainerDifficulty(String v) =>
      _prefs.setString(_kTrainerDifficulty, v);

  int getTrainerBest(String difficulty, [int fallback = 0]) =>
      _prefs.getInt('$_kTrainerBestPrefix$difficulty') ?? fallback;
  Future<void> setTrainerBest(String difficulty, int v) =>
      _prefs.setInt('$_kTrainerBestPrefix$difficulty', v);

  // —— 指弹(第59步·按歌存)——
  // 奏法: strum = 扫弦(老行为), fingerpick = 指弹。按歌存——不同歌可能适合不同奏法。
  String getPlayStyle(String songId, [String fallback = 'strum']) =>
      _prefs.getString('$_kPlayStylePrefix$songId') ?? fallback;
  Future<void> setPlayStyle(String songId, String v) =>
      _prefs.setString('$_kPlayStylePrefix$songId', v);

  // 指弹节奏型下标(当前歌)。跨歌不串:每首歌自己的练习偏好。
  int getFingerpickPattern(String songId, [int fallback = 0]) =>
      _prefs.getInt('$_kFingerpickPatternPrefix$songId') ?? fallback;
  Future<void> setFingerpickPattern(String songId, int v) =>
      _prefs.setInt('$_kFingerpickPatternPrefix$songId', v);

  // key 常量:集中放一处,免得读写各处拼字符串拼错。
  static const _kSongIndex = 'pref_song_index'; // 旧版:上次选歌下标(第45步前)。留作一次性迁移读。
  static const _kSelectedSongId = 'pref_selected_song_id'; // 第45步起:上次选歌按 id 存(替 _kSongIndex)
  static const _kPatternIndex = 'pref_pattern_index';
  static const _kStrumSound = 'pref_strum_sound';
  static const _kRamp = 'pref_ramp';
  static const _kLyricScale = 'pref_lyric_scale';
  static const _kA4 = 'pref_a4'; // 调音器 A4 校准基准(Hz)
  static const _kThemeMode = 'pref_theme_mode'; // 第47步:主题 system/light/dark
  static const _kTrainerChordA = 'pref_trainer_chord_a'; // 换和弦训练:上次选的和弦 A
  static const _kTrainerChordB = 'pref_trainer_chord_b'; // 换和弦训练:上次选的和弦 B
  static const _kTrainerBpm = 'pref_trainer_bpm'; // 换和弦训练:速度
  static const _kTrainerBeats = 'pref_trainer_beats'; // 换和弦训练:每几拍换
  static const _kTrainerChallenge = 'pref_trainer_challenge'; // 换和弦训练:60 秒挑战开关
  static const _kUserSongs = 'pref_user_songs'; // 用户自加的歌:JSON 字符串列表
  static const _kUserSongSeq = 'pref_user_song_seq'; // 用户歌 id 计数器(u1、u2…)
  static const _kTempoPrefix = 'pref_tempo_'; // 后接歌曲 id,如 pref_tempo_0(内置)、pref_tempo_u1(用户)
  static const _kTransposePrefix = 'pref_transpose_'; // 后接歌曲 id;移调半音偏移(0=不移调)
  static const _kAbAPrefix = 'pref_ab_a_'; // 后接歌曲 id
  static const _kAbBPrefix = 'pref_ab_b_';
  static const _kLoopsPrefix = 'pref_loops_'; // 后接歌曲 id
  static const _kSecPrefix = 'pref_sec_'; // 后接歌曲 id
  static const _kPracticeDays = 'pref_practice_days'; // 'yyyy-MM-dd' 字符串列表
  static const _kLastPracticedPrefix = 'pref_last_practiced_'; // 后接歌曲 id;上次练习日期 ISO string
  static const _kFavorites = 'pref_favorites'; // 第58步-2:收藏歌曲 id 列表
  static const _kDailyGoalMin = 'pref_daily_goal_min'; // 第58步-3:每日练琴目标(分钟,默认30)
  static const _kTodaySec = 'pref_today_sec'; // 第58步-3:今天已练秒数
  static const _kTodaySecDate = 'pref_today_sec_date'; // 第58步-3:上面秒数对应的日期
  static const _kReminderEnabled = 'pref_reminder_enabled'; // 第58步-4:练习提醒开关
  static const _kReminderHour = 'pref_reminder_hour'; // 第58步-4:提醒时间-时(默认19)
  static const _kReminderMinute = 'pref_reminder_minute'; // 第58步-4:提醒时间-分(默认0)
  static const _kMetronomeSound = 'pref_metronome_sound'; // 第58步-5:节拍器音色名
  static const _kTrainerDifficulty = 'pref_trainer_difficulty'; // 第58步-7:换和弦难度名
  static const _kTrainerBestPrefix = 'pref_trainer_best_'; // 第58步-7:后接难度名,如 pref_trainer_best_beginner
  static const _kPlayStylePrefix = 'pref_play_style_'; // 第59步:后接歌曲 id;奏法 strum/fingerpick
  static const _kFingerpickPatternPrefix = 'pref_fingerpick_pattern_'; // 第59步:后接歌曲 id;指弹节奏型下标
}
