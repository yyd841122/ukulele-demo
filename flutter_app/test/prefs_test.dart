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

  test('上次选的歌 / 节奏型:存了能读回,没存过给默认值', () async {
    final p = await AppPreferences.load();
    expect(p.getSongIndex(0), 0); // 没存过 → fallback
    expect(p.getPatternIndex(1), 1);

    await p.setSongIndex(3);
    await p.setPatternIndex(2);

    // 重新加载 = 模拟 app 重启
    final p2 = await AppPreferences.load();
    expect(p2.getSongIndex(0), 3);
    expect(p2.getPatternIndex(0), 2);
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
}
