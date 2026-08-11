// 第79步回归测试:练习栏(PracticeBar)在大字体 + 窄屏下不得横向溢出。
// 黄黑斑马纹 = Flutter 的 RenderFlex 溢出指示。用户反馈练习 tab 调速那行出现斑马纹,
// 根因是「调速」文字和「BPM」文字会随系统字体放大撑爆。这里用 textScale 1.5 + 320 宽
// 复现该条件,断言泵完不抛任何异常(takeException 为 null)。
//
// 只泵 PracticeBar 一个部件(配假数据),不依赖音频引擎 / SoLoud,跑得快、隔离干净。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ukulele_demo/models.dart';
import 'package:ukulele_demo/widgets/practice_bar.dart';

void main() {
  testWidgets('练习栏在大字体窄屏下不溢出(无斑马纹)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320, // 窄屏(老款 / 小屏),调速行最容易在这挤爆
            child: MediaQuery(
              // 模拟系统大字体(常见:长辈 / 近视用户),文字放大后撑爆 Row
              data: MediaQueryData(textScaler: TextScaler.linear(1.5)),
              child: SingleChildScrollView(
                child: PracticeBar(
                  lineChords: const ['C', 'G', 'Am', 'F'],
                  currentChordIndex: 0,
                  slot: 0,
                  beatsPerChord: 4,
                  strumGrid: const [
                    StrumDir.down, StrumDir.rest, StrumDir.down, StrumDir.up,
                    StrumDir.down, StrumDir.rest, StrumDir.down, StrumDir.up,
                  ],
                  patternNames: const ['全下', '下上', '海岛', '民谣', '摇滚'],
                  patternIndex: 0,
                  onPatternChanged: (_) {},
                  abActive: false,
                  onClearAb: () {},
                  countInNumber: 0,
                  nextChord: 'G',
                  tempo: 180, // 三位数 BPM,文字最长,最容易撑爆 BPM 那格
                  minTempo: 90,
                  maxTempo: 180,
                  onTempoChanged: (_) {},
                  isPlaying: false,
                  canPlay: true,
                  onTogglePlay: () {},
                  strumSoundOn: true,
                  onToggleStrumSound: () {},
                  rampOn: false,
                  onToggleRamp: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // 调速滑块渲染出来了 → 练习栏确实画了(含调速行)
    expect(find.byType(Slider), findsOneWidget);
    // 关键:整个泵过程没有抛 RenderFlex 溢出异常(那才是斑马纹)。
    expect(tester.takeException(), isNull);
  });
}
