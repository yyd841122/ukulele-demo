// 指弹谱自动生成(第68步):从歌曲和弦序列+指弹型+chordShapes 生成 TAB 谱数据。
// 纯 Dart(无 Flutter 依赖),可无头测试。
import '../models.dart';
import '../widgets/fretboard_view.dart';

/// 从拍扁的和弦序列 + 指弹节奏型生成整首曲谱(TabNote 列表)。
/// [flatChords] = 按顺序排列的和弦名列表(SongScreen 的 _flat)。
/// [pattern] = 选中的指弹节奏型。
/// [beatsPerChord] = 每个和弦持续几拍。
/// 产出长度 = flatChords.length × beatsPerChord × 2(8分音符槽位)。
List<TabNote> generateTabNotes(List<String> flatChords, FingerpickPattern pattern, int beatsPerChord) {
  final grid = pattern.grid(beatsPerChord);
  final result = <TabNote>[];

  for (final chord in flatChords) {
    final frets = chordShapes[chord];
    for (var s = 0; s < grid.length; s++) {
      final stringIdx = grid[s];
      if (stringIdx == null) {
        result.add(const TabNote.rest());
      } else if (frets != null && stringIdx >= 0 && stringIdx < frets.length) {
        result.add(TabNote(stringIndex: stringIdx, fret: frets[stringIdx]));
      } else {
        // chordShapes 里没有这个和弦或弦号越界:退回空弦(0)
        result.add(TabNote(stringIndex: stringIdx, fret: 0));
      }
    }
  }

  return result;
}
