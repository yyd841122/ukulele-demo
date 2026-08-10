// 指弹谱自动生成测试(第68步):generateTabNotes 纯逻辑。
import 'package:flutter_test/flutter_test.dart';
import 'package:ukulele_demo/models.dart';
import 'package:ukulele_demo/scoring/tab_generator.dart';
import 'package:ukulele_demo/widgets/fretboard_view.dart';

void main() {
  group('generateTabNotes', () {
    test('空和弦序列返回空列表', () {
      final notes = generateTabNotes([], fingerpickPatternsFor(4).first, 4);
      expect(notes, isEmpty);
    });

    test('单个 C 和弦+4321琶音:生成 8 个槽位(4拍×2),含正确品位', () {
      final fp = fingerpickPatternsFor(4).firstWhere((f) => f.name == '4321 琶音');
      final notes = generateTabNotes(['C'], fp, 4);
      // C = [0,0,0,3](G,C,E,A 顺序)
      // 4321 琶音 grid: [0,1,2,3, 0,1,2,3](stringIndex)
      expect(notes.length, 8); // 1 和弦 × 4 拍 × 2 槽

      // 槽0: G弦(stringIndex=0), C和弦frets[0]=0
      expect(notes[0].isRest, false);
      expect(notes[0].stringIndex, 0);
      expect(notes[0].fret, 0);

      // 槽1: C弦(stringIndex=1), frets[1]=0
      expect(notes[1].isRest, false);
      expect(notes[1].stringIndex, 1);
      expect(notes[1].fret, 0);

      // 槽2: E弦(stringIndex=2), frets[2]=0
      expect(notes[2].stringIndex, 2);
      expect(notes[2].fret, 0);

      // 槽3: A弦(stringIndex=3), frets[3]=3
      expect(notes[3].stringIndex, 3);
      expect(notes[3].fret, 3);
    });

    test('两个和弦+全下拨:每个和弦 8 槽,总共 16 槽', () {
      final fp = fingerpickPatternsFor(4).firstWhere((f) => f.name == '全下拨');
      final notes = generateTabNotes(['C', 'G'], fp, 4);
      // C×8 + G×8 = 16
      expect(notes.length, 16);

      // 全下拨:偶数槽=0(G弦),奇数槽=null(休止)
      expect(notes[0].isRest, false);
      expect(notes[0].stringIndex, 0); // G 弦
      expect(notes[1].isRest, true); // 休止

      // 第 8 槽(G 和弦):G 和弦 frets=[0,2,3,2], stringIndex=0(G弦) → fret=0
      expect(notes[8].stringIndex, 0);
      expect(notes[8].fret, 0);
    });

    test('未知和弦(tabGenerator 不认识)退回空弦', () {
      final fp = fingerpickPatternsFor(4).first;
      final notes = generateTabNotes(['Xyz'], fp, 4);
      // chordShapes 不认识 → fret=0 兜底
      expect(notes[0].fret, 0);
      expect(notes[0].isRest, false);
    });

    test('TabNote.rest() 标记正确', () {
      final r = const TabNote.rest();
      expect(r.isRest, true);
    });
  });
}
