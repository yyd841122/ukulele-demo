// 自由指弹练习(第64步):不跟整首歌,选一个和弦 + 一个指弹型,按自己速度循环练习。
// 嵌入现有练习页(SongScreen)做"子模式"——复用 IndexedStack 保活架构。
// 入口:练习栏「自由指弹」按钮→进入子模式(切换回扫弦则退出)。
//
// 纯 Dart(无 Flutter 依赖):提供和弦循环状态、当前指弹型管理,UI 在 practice_bar 和 song_screen 里处理。
import '../models.dart';

/// 自由指弹练习状态:选一个和弦+一个指弹型,循环练。
class FreeFingerpickSession {
  /// 可练的和弦列表(从当前歌的 chordShapes 里取)。
  final List<String> chords;

  /// 当前选中的和弦下标。
  int _chordIndex = 0;

  /// 当前选中的指弹型下标。
  int _patternIndex = 0;

  FreeFingerpickSession({required this.chords});

  String get currentChord => chords.isNotEmpty ? chords[_chordIndex.clamp(0, chords.length - 1)] : 'C';

  FingerpickPattern get currentPattern {
    final fps = fingerpickPatternsFor(4); // 自由模式固定 4 拍
    return fps[_patternIndex.clamp(0, fps.length - 1)];
  }

  /// 换到下一个和弦(循环)。
  void nextChord() {
    if (chords.isEmpty) return;
    _chordIndex = (_chordIndex + 1) % chords.length;
  }

  /// 换到上一个和弦(循环)。
  void prevChord() {
    if (chords.isEmpty) return;
    _chordIndex = (_chordIndex - 1) % chords.length;
  }

  /// 选第 i 个指弹型。
  void setPattern(int i) {
    final fps = fingerpickPatternsFor(4);
    _patternIndex = i.clamp(0, fps.length - 1);
  }
}
