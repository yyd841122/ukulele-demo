// 持久化层(AppPreferences)的无头单元测试。
// 不连手机(flutter test):验证"存了能读回 / 按歌不串 / AB 成对清"。
// shared_preferences 在 flutter_test 里是自动 mock 的内存库,setMockInitialValues 给每个测试一个干净起点。
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ukulele_demo/models.dart'; // practiceDayKey:断言标记的是今天的日期键
import 'package:ukulele_demo/prefs/app_preferences.dart';

void main() {
  setUp(() {
    // 每个测试前重置成空 mock,免得测试之间互相污染。
    SharedPreferences.setMockInitialValues({});
  });

  test('上次选的歌(按 id)/ 节奏型:存了能读回,没存过给默认值', () async {
    final p = await AppPreferences.load();
    expect(p.getSelectedSongId(), isNull); // 没存过 → null
    expect(p.getPatternIndex(1), 1);

    await p.setSelectedSongId('u2');
    await p.setPatternIndex(2);

    // 重新加载 = 模拟 app 重启
    final p2 = await AppPreferences.load();
    expect(p2.getSelectedSongId(), 'u2');
    expect(p2.getPatternIndex(0), 2);
  });

  test('一次性迁移:旧版按下标存的下标读得回(迁移写在新键,由 song_screen 触发)', () async {
    // 模拟旧版写过的"按下标存"值
    SharedPreferences.setMockInitialValues({'pref_song_index': 3});
    final p = await AppPreferences.load();
    expect(p.getSelectedSongId(), isNull); // 新键还没写过(迁移还没跑)
    expect(p.getLegacySongIndex(-1), 3); // 旧下标读得回 → 迁移拿它换算成 id
  });

  test('速度按歌存:不同歌互不串', () async {
    final p = await AppPreferences.load();
    expect(p.getTempo('a'), isNull); // 没存过 → null(调用方据此用原速)

    await p.setTempo('a', 90);
    await p.setTempo('b', 120);

    final p2 = await AppPreferences.load();
    expect(p2.getTempo('a'), 90);
    expect(p2.getTempo('b'), 120);
    expect(p2.getTempo('c'), isNull); // 别的歌没存
  });

  test('移调(虚拟变调夹)按歌存:存了能读回、没存过给默认 0、不同歌不串', () async {
    final p = await AppPreferences.load();
    expect(p.getTranspose('a'), 0); // 没存过 → 0(不移调)

    await p.setTranspose('a', 3);
    await p.setTranspose('b', -5);

    final p2 = await AppPreferences.load(); // 模拟重启
    expect(p2.getTranspose('a'), 3);
    expect(p2.getTranspose('b'), -5);
    expect(p2.getTranspose('c'), 0); // 别的歌没存 → 0
  });

  test('AB 区间:成对存 / 成对清', () async {
    final p = await AppPreferences.load();
    expect(p.getAb('x'), isNull); // 没设过

    await p.setAb('x', 1, 3);
    var p2 = await AppPreferences.load();
    expect(p2.getAb('x')!.a, 1);
    expect(p2.getAb('x')!.b, 3);

    // 清除(两个都传 null)
    await p2.setAb('x', null, null);
    p2 = await AppPreferences.load();
    expect(p2.getAb('x'), isNull);
  });

  test('AB 按歌存:不同歌的区间不串', () async {
    final p = await AppPreferences.load();
    await p.setAb('m', 1, 2);
    await p.setAb('n', 5, 7);

    final p2 = await AppPreferences.load();
    expect(p2.getAb('m')!.a, 1);
    expect(p2.getAb('n')!.b, 7);
  });

  test('练琴打卡:累计遍数 + 秒数,存了能读回、按歌不串', () async {
    final p = await AppPreferences.load();
    expect(p.getLoops('s1'), 0); // 没存过 → 0
    expect(p.getSec('s1'), 0);

    await p.setLoops('s1', 5);
    await p.setSec('s1', 320);

    final p2 = await AppPreferences.load(); // 模拟重启
    expect(p2.getLoops('s1'), 5);
    expect(p2.getSec('s1'), 320);
    expect(p2.getLoops('s2'), 0); // 别的歌没存 → 0
    expect(p2.getSec('s2'), 0);
  });

  test('歌词字号:存了能读回,没存过给默认 1.0', () async {
    final p = await AppPreferences.load();
    expect(p.getLyricScale(), 1.0); // 没存过 → 默认

    await p.setLyricScale(1.4);

    final p2 = await AppPreferences.load(); // 模拟重启
    expect(p2.getLyricScale(), 1.4);
    expect(p2.getLyricScale(0.9), 1.4); // 存过就忽略 fallback
  });

  test('练习日历:标记今天练过(去重)+ 能读回', () async {
    final p = await AppPreferences.load();
    expect(p.getPracticeDays(), isEmpty); // 没记过

    await p.markPracticedToday();
    await p.markPracticedToday(); // 同一天再调一次 → 去重,不重复加

    final days = p.getPracticeDays();
    expect(days.length, 1); // 去重:今天只记一次
    expect(days, contains(practiceDayKey(DateTime.now())));

    // 模拟重启仍读得到
    final p2 = await AppPreferences.load();
    expect(p2.getPracticeDays().length, 1);
  });

  test('A4 校准:存了能读回,没存过给默认 440', () async {
    final p = await AppPreferences.load();
    expect(p.getA4(), 440); // 没存过 → 默认标准音高

    await p.setA4(442); // 调成交响音高

    final p2 = await AppPreferences.load(); // 模拟重启
    expect(p2.getA4(), 442);
  });

  test('主题模式:存了能读回,没存过给默认 system', () async {
    final p = await AppPreferences.load();
    expect(p.getThemeMode(), 'system'); // 没存过 → 默认

    await p.setThemeMode('dark');

    final p2 = await AppPreferences.load(); // 模拟重启
    expect(p2.getThemeMode(), 'dark');
  });

  test('clearSong:清掉某首歌的所有偏好(删用户歌时调)', () async {
    final p = await AppPreferences.load();
    await p.setTempo('u1', 90);
    await p.setTranspose('u1', 4);
    await p.setAb('u1', 2, 5);
    await p.setLoops('u1', 7);
    await p.setSec('u1', 200);

    await p.clearSong('u1');

    final p2 = await AppPreferences.load(); // 模拟重启
    expect(p2.getTempo('u1'), isNull);
    expect(p2.getTranspose('u1'), 0); // 移调也清掉 → 回到默认 0
    expect(p2.getAb('u1'), isNull);
    expect(p2.getLoops('u1'), 0);
    expect(p2.getSec('u1'), 0);
  });

  test('换和弦训练:弦对/速度/档位/挑战,存了能读回、没存过给默认', () async {
    final p = await AppPreferences.load();
    // 没存过 → 调用方给的 fallback
    expect(p.getTrainerChordA('C'), 'C');
    expect(p.getTrainerChordB('G'), 'G');
    expect(p.getTrainerBpm(60), 60);
    expect(p.getTrainerBeats(4), 4);
    expect(p.getTrainerChallenge(), false);

    await p.setTrainerChordA('Am');
    await p.setTrainerChordB('F');
    await p.setTrainerBpm(80);
    await p.setTrainerBeats(2);
    await p.setTrainerChallenge(true);

    final p2 = await AppPreferences.load(); // 模拟重启
    expect(p2.getTrainerChordA('C'), 'Am');
    expect(p2.getTrainerChordB('G'), 'F');
    expect(p2.getTrainerBpm(60), 80);
    expect(p2.getTrainerBeats(4), 2);
    expect(p2.getTrainerChallenge(), true);
    expect(p2.getTrainerChallenge(false), true); // 存过就忽略 fallback
  });

  test('指弹练习偏好:曲谱/示范音/速度 存读往返 + 默认值', () async {
    final p = await AppPreferences.load();
    expect(p.getFingerpickScore(), 0); // 默认第 0 首
    expect(p.getFingerpickSound(), true); // 默认开
    expect(p.getFingerpickTempo(), isNull); // 没存过 → null(用曲谱默认速度)

    await p.setFingerpickScore(3);
    await p.setFingerpickSound(false);
    await p.setFingerpickTempo(120);

    final p2 = await AppPreferences.load(); // 模拟重启
    expect(p2.getFingerpickScore(), 3);
    expect(p2.getFingerpickSound(), false);
    expect(p2.getFingerpickTempo(), 120);
    expect(p2.getFingerpickScore(9), 3); // 存过就忽略 fallback
  });

  test('琶音练习偏好:进行/拨弦型/示范音/速度 存读往返 + 默认值', () async {
    final p = await AppPreferences.load();
    expect(p.getArpStudy(), 0);
    expect(p.getArpPattern(), 0);
    expect(p.getArpSound(), true);
    expect(p.getArpTempo(), isNull);

    await p.setArpStudy(2);
    await p.setArpPattern(1);
    await p.setArpSound(false);
    await p.setArpTempo(90);

    final p2 = await AppPreferences.load();
    expect(p2.getArpStudy(), 2);
    expect(p2.getArpPattern(), 1);
    expect(p2.getArpSound(), false);
    expect(p2.getArpTempo(), 90);
  });

  test('统计备份合并:打卡日历并集去重 + 每日目标取备份值(完善Step5)', () async {
    // 现有:练过 2026-01-01、目标 30 分
    SharedPreferences.setMockInitialValues({
      'pref_practice_days': ['2026-01-01'],
      'pref_daily_goal_min': 30,
    });
    final p = await AppPreferences.load();
    expect(p.getStatsPayload()['practiceDays'], ['2026-01-01']);
    expect(p.getStatsPayload()['dailyGoalMin'], 30);

    // 合入备份:打卡 2026-01-01(重复)+ 2026-02-03(新)、目标 45
    final n = await p.applyStatsPayload({
      'practiceDays': ['2026-01-01', '2026-02-03'],
      'dailyGoalMin': 45,
    });

    expect(n, 2); // 并集去重后 2 天
    final p2 = await AppPreferences.load(); // 模拟重启
    expect(p2.getPracticeDays(), ['2026-01-01', '2026-02-03']); // 排序后
    expect(p2.getDailyGoalMin(), 45); // 取备份值
  });

  test('applyStatsPayload 幂等:同一份重复导入打卡不翻倍', () async {
    SharedPreferences.setMockInitialValues({});
    final p = await AppPreferences.load();
    final stats = {'practiceDays': ['2026-01-01', '2026-01-02'], 'dailyGoalMin': 20};
    await p.applyStatsPayload(stats);
    await p.applyStatsPayload(stats); // 再来一次
    final p2 = await AppPreferences.load();
    expect(p2.getPracticeDays(), ['2026-01-01', '2026-01-02']); // 仍 2 天,没翻倍
  });

  test('录音戴耳机提示(完善Step9):没看过→false默认,标记后→true,重启仍记得', () async {
    final p = await AppPreferences.load();
    expect(p.getRecordTipSeen(), isFalse); // 没存过 → false(首次开录要弹)

    await p.setRecordTipSeen(true);
    final p2 = await AppPreferences.load(); // 模拟重启
    expect(p2.getRecordTipSeen(), isTrue); // 标记过、重启仍记得 → 不再弹
  });
}
