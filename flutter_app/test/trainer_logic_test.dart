// 换和弦训练·多和弦的纯函数无头单元测试(新功能Step16)。
// 测三样:nextTrainerIndex(下一个切到哪)/ sanitizeTrainerChords(清洗存的序列)/
// trainerPresets 合法性卡口(和弦名都在 chordShapes 里、相邻不重复——照 arpeggio_test 的先例,
// 以后改预设写错和弦名,测试直接红)。
// 把切换逻辑抽成纯函数(随机性由调用方传 Random),就是为了这里能直接、稳定地测。
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:ukulele_demo/models.dart';

void main() {
  group('nextTrainerIndex 下一个下标', () {
    final rnd = Random();

    test('顺序模式:推进一位,越过末尾转圈', () {
      expect(nextTrainerIndex(4, 0, random: false, rnd: rnd), 1);
      expect(nextTrainerIndex(4, 2, random: false, rnd: rnd), 3);
      expect(nextTrainerIndex(4, 3, random: false, rnd: rnd), 0); // 末尾 → 回开头
      expect(nextTrainerIndex(2, 1, random: false, rnd: rnd), 0); // 两个和弦也是转圈
    });

    test('随机模式:循环 1000 次永不等于当前(切了等于没切是 bug)', () {
      for (var len = 2; len <= 5; len++) {
        for (var idx = 0; idx < len; idx++) {
          for (var i = 0; i < 1000; i++) {
            expect(nextTrainerIndex(len, idx, random: true, rnd: rnd) != idx, isTrue,
                reason: 'len=$len idx=$idx 第 $i 次抽到了自己');
          }
        }
      }
    });

    test('随机模式:每个"别的"位置都能被抽到(不会只盯着某几个)', () {
      for (var len = 2; len <= 5; len++) {
        const idx = 0;
        final seen = <int>{};
        for (var i = 0; i < 2000; i++) {
          seen.add(nextTrainerIndex(len, idx, random: true, rnd: rnd));
        }
        // 除当前外的 len-1 个位置都得出现过
        expect(seen.length, len - 1, reason: 'len=$len 只抽到了 $seen');
      }
    });

    test('序列退化(len<2):不动,防崩', () {
      expect(nextTrainerIndex(1, 0, random: true, rnd: rnd), 0);
      expect(nextTrainerIndex(1, 0, random: false, rnd: rnd), 0);
    });
  });

  group('sanitizeTrainerChords 清洗序列', () {
    test('合法序列原样通过(不去非相邻重复——卡农里 C 出现两次是合法的)', () {
      expect(
        sanitizeTrainerChords(['C', 'G', 'Am', 'Em', 'F', 'C', 'F', 'G']),
        ['C', 'G', 'Am', 'Em', 'F', 'C', 'F', 'G'],
      );
    });

    test('去掉 chordShapes 里没有的(以后删和弦防失效)', () {
      expect(
        sanitizeTrainerChords(['C', 'Xx', 'G']),
        ['C', 'G'],
      );
    });

    test('去掉线性相邻重复(相邻相同 = 切了等于没切)', () {
      expect(
        sanitizeTrainerChords(['C', 'C', 'G', 'G', 'G', 'Am']),
        ['C', 'G', 'Am'],
      );
    });

    test('清完不足 2 个 → 返回空表(调用方走 fallback)', () {
      expect(sanitizeTrainerChords(['C']), const []);
      expect(sanitizeTrainerChords(['C', 'C']), const []); // 去重后只剩 1 个
      expect(sanitizeTrainerChords(['Xx', 'Yy']), const []); // 全都不认识
      expect(sanitizeTrainerChords([]), const []);
    });
  });

  group('trainerPresets 预设合法性卡口', () {
    test('每条预设:和弦都在 chordShapes 里(写错名画不出图/放不出声)', () {
      for (final p in trainerPresets) {
        for (final c in p.chords) {
          expect(chordShapes.containsKey(c), isTrue,
              reason: '${p.name} 里的 $c 不在 chordShapes');
        }
      }
    });

    test('每条预设:线性相邻不重复(切和弦要有意义)', () {
      for (final p in trainerPresets) {
        for (var i = 1; i < p.chords.length; i++) {
          expect(p.chords[i] != p.chords[i - 1], isTrue,
              reason: '${p.name} 第 $i 个跟前一个重复');
        }
      }
    });

    test('每条预设:长度 ≥ 2(至少要有东西可换)', () {
      for (final p in trainerPresets) {
        expect(p.chords.length >= 2, isTrue, reason: '${p.name} 少于 2 个和弦');
      }
    });
  });
}
