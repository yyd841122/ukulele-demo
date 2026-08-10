// 跟弹打分引擎测试(第61步):OnsetDetector + TimingScorer + SessionScore。
// 纯 Dart 无头测试,不依赖 Flutter。
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ukulele_demo/scoring/scoring_engine.dart';

Float64List _tone(double amplitude, int samples) {
  final out = Float64List(samples);
  for (var i = 0; i < samples; i++) {
    out[i] = amplitude * sin(2 * pi * 440 * i / 44100);
  }
  return out;
}

Float64List _silence(int samples) => Float64List(samples);

void main() {
  group('OnsetDetector', () {
    test('纯静音不触发', () {
      final d = OnsetDetector();
      d.reset();
      var triggered = false;
      for (var i = 0; i < 100; i++) {
        if (d.feed(_silence(512))) triggered = true;
      }
      expect(triggered, false);
    });

    test('突发的响音触发一次 onset', () {
      final d = OnsetDetector(threshold: 0.01);
      d.reset();
      // 先喂足够静音
      for (var i = 0; i < 10; i++) d.feed(_silence(1024));
      // 再喂响音
      var onsets = 0;
      for (var i = 0; i < 5; i++) {
        if (d.feed(_tone(0.5, 512))) onsets++;
      }
      expect(onsets, 1); // 第一次响触发一次,之后不再触发(还在"响"中)
    });

    test('两次间隔够长的响声各触发一次 onset', () {
      final d = OnsetDetector(threshold: 0.01, minSilenceMs: 50);
      d.reset();
      // 足够静音后再响
      for (var i = 0; i < 10; i++) d.feed(_silence(1024));
      var onsets = 0;
      onsets += d.feed(_tone(0.5, 1024)) ? 1 : 0; // 第一声(一个长帧够触发)
      // 继续静音直到重新恢复
      for (var i = 0; i < 10; i++) d.feed(_silence(1024));
      // 第二声
      onsets += d.feed(_tone(0.5, 1024)) ? 1 : 0;
      expect(onsets, 2);
    });

    test('reset 清状态', () {
      final d = OnsetDetector(threshold: 0.01);
      d.reset();
      for (var i = 0; i < 5; i++) d.feed(_silence(1024));
      expect(d.feed(_tone(0.5, 512)), true); // 触发了
      d.reset();
      for (var i = 0; i < 5; i++) d.feed(_silence(1024));
      expect(d.feed(_tone(0.5, 512)), true); // reset 后又可以触发
    });
  });

  group('TimingScorer', () {
    final now = DateTime(2026, 8, 10, 12, 0, 0, 0);

    test('偏差 0ms → good', () {
      final r = TimingScorer.judge(now, now);
      expect(r.judgment, BeatJudgment.good);
      expect(r.deviationMs, 0);
    });

    test('偏差 ±40ms → good(在 80ms 容差内)', () {
      expect(TimingScorer.judge(now, now.add(const Duration(milliseconds: 40))).judgment, BeatJudgment.good);
      expect(TimingScorer.judge(now, now.subtract(const Duration(milliseconds: 40))).judgment, BeatJudgment.good);
    });

    test('偏差 -120ms → early(>80ms 且 <250ms)', () {
      final r = TimingScorer.judge(now, now.subtract(const Duration(milliseconds: 120)));
      expect(r.judgment, BeatJudgment.early);
      expect(r.deviationMs, -120);
    });

    test('偏差 +150ms → late', () {
      final r = TimingScorer.judge(now, now.add(const Duration(milliseconds: 150)));
      expect(r.judgment, BeatJudgment.late);
      expect(r.deviationMs, 150);
    });

    test('偏差 +300ms → missed(超过 250ms 最大偏差)', () {
      final r = TimingScorer.judge(now, now.add(const Duration(milliseconds: 300)));
      expect(r.judgment, BeatJudgment.missed);
    });

    test('没检测到(actual=null) → missed', () {
      final r = TimingScorer.judge(now, null);
      expect(r.judgment, BeatJudgment.missed);
    });
  });

  group('SessionScore', () {
    test('全 good → accuracy 1.0, grade S', () {
      final s = SessionScore();
      for (var i = 0; i < 10; i++) s.record(BeatJudgment.good);
      expect(s.accuracy, 1.0);
      expect(s.grade, 'S');
    });

    test('一半 good 一半 missed → accuracy 0.5, grade C', () {
      final s = SessionScore();
      for (var i = 0; i < 5; i++) s.record(BeatJudgment.good);
      for (var i = 0; i < 5; i++) s.record(BeatJudgment.missed);
      expect(s.accuracy, closeTo(0.5, 0.01));
      expect(s.grade, 'C');
    });

    test('8/10 good → accuracy 0.8, grade B', () {
      final s = SessionScore();
      for (var i = 0; i < 8; i++) s.record(BeatJudgment.good);
      s.record(BeatJudgment.early);
      s.record(BeatJudgment.late);
      expect(s.accuracy, closeTo(0.8, 0.01));
      expect(s.grade, 'B');
    });

    test('等级边界:S≥0.95, A≥0.85, B≥0.70, C≥0.50, D<0.50', () {
      SessionScore s;

      s = SessionScore(); for (var i = 0; i < 95; i++) { s.record(BeatJudgment.good); }
      for (var i = 0; i < 5; i++) { s.record(BeatJudgment.missed); }
      expect(s.grade, 'S');

      s = SessionScore(); for (var i = 0; i < 85; i++) { s.record(BeatJudgment.good); }
      for (var i = 0; i < 15; i++) { s.record(BeatJudgment.missed); }
      expect(s.grade, 'A');

      s = SessionScore(); for (var i = 0; i < 70; i++) { s.record(BeatJudgment.good); }
      for (var i = 0; i < 30; i++) { s.record(BeatJudgment.missed); }
      expect(s.grade, 'B');

      s = SessionScore(); for (var i = 0; i < 50; i++) { s.record(BeatJudgment.good); }
      for (var i = 0; i < 50; i++) { s.record(BeatJudgment.missed); }
      expect(s.grade, 'C');

      s = SessionScore(); for (var i = 0; i < 49; i++) { s.record(BeatJudgment.good); }
      for (var i = 0; i < 51; i++) { s.record(BeatJudgment.missed); }
      expect(s.grade, 'D');
    });

    test('total=0 时 accuracy=0, grade=—', () {
      final s = SessionScore();
      expect(s.accuracy, 0);
      expect(s.grade, '—');
    });

    test('reset 清空所有计数', () {
      final s = SessionScore();
      for (var i = 0; i < 10; i++) { s.record(BeatJudgment.good); }
      s.reset();
      expect(s.total, 0);
      expect(s.good, 0);
    });
  });
}
