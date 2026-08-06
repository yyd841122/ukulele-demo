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
    expect(p.getTempo(0), isNull); // 没存过 → null(调用方据此用原速)

    await p.setTempo(0, 90);
    await p.setTempo(1, 120);

    final p2 = await AppPreferences.load();
    expect(p2.getTempo(0), 90);
    expect(p2.getTempo(1), 120);
    expect(p2.getTempo(2), isNull); // 别的歌没存
  });

  test('AB 区间:成对存 / 成对清', () async {
    final p = await AppPreferences.load();
    expect(p.getAb(0), isNull); // 没设过

    await p.setAb(0, 1, 3);
    var p2 = await AppPreferences.load();
    expect(p2.getAb(0)!.a, 1);
    expect(p2.getAb(0)!.b, 3);

    // 清除(两个都传 null)
    await p2.setAb(0, null, null);
    p2 = await AppPreferences.load();
    expect(p2.getAb(0), isNull);
  });

  test('AB 按歌存:不同歌的区间不串', () async {
    final p = await AppPreferences.load();
    await p.setAb(0, 1, 2);
    await p.setAb(3, 5, 7);

    final p2 = await AppPreferences.load();
    expect(p2.getAb(0)!.a, 1);
    expect(p2.getAb(3)!.b, 7);
  });

  test('练琴打卡:累计遍数 + 秒数,存了能读回、按歌不串', () async {
    final p = await AppPreferences.load();
    expect(p.getLoops(0), 0); // 没存过 → 0
    expect(p.getSec(0), 0);

    await p.setLoops(0, 5);
    await p.setSec(0, 320);

    final p2 = await AppPreferences.load(); // 模拟重启
    expect(p2.getLoops(0), 5);
    expect(p2.getSec(0), 320);
    expect(p2.getLoops(1), 0); // 别的歌没存 → 0
    expect(p2.getSec(1), 0);
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
}
