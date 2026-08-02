// 尤克里里弹唱练习 —— 数据模型。
//
// 概念叫法统一见仓库根目录 CONTEXT.md:
//   Song(歌曲) → Section(段落) → Line(歌词行) → Chord(和弦)
//
// 这个文件【只放数据长什么样】,不放界面。界面在 main.dart。
// 把数据和界面分开是这一步最值得记住的习惯:以后换布局、加节拍器,
// 都不用动这里;加新歌也只是往底下加一行数据。
import 'package:flutter/foundation.dart';

/// 一行歌词 + 压在它上方的和弦序列(按出现顺序)。
/// 例如 chords: ["C","G","Am","F"]  lyric: "Somewhere over the rainbow..."
@immutable
class Line {
  final List<String> chords;
  final String lyric;

  const Line({required this.chords, required this.lyric});
}

/// 歌曲里的一个段落,例如"副歌"。name 可空 —— 第一段常常没有名字。
@immutable
class Section {
  final String? name;
  final List<Line> lines;

  const Section({this.name, required this.lines});
}

/// 一首可练习的歌。
///
/// - tempo:速度(BPM,每分钟多少拍)
/// - beatsPerChord:一个和弦持续几拍后换下一个
///
/// 这两个值这一步【先存着、只显示】;真正用上它们(节拍器)是后面的切片。
@immutable
class Song {
  final String title;
  final int tempo;
  final int beatsPerChord;
  final List<Section> sections;

  const Song({
    required this.title,
    required this.tempo,
    this.beatsPerChord = 4,
    required this.sections,
  });
}

/// 超薄切片用的样例歌:Somewhere Over the Rainbow。
/// 数据直接照搬 Web 版(index.html 里的 SONGS[0]),保证两版内容一致、便于对照。
const Song sampleSong = Song(
  title: '🌈 Somewhere Over the Rainbow',
  tempo: 72,
  beatsPerChord: 4,
  sections: [
    Section(lines: [
      Line(
        chords: ['C', 'G', 'Am', 'F'],
        lyric: 'Somewhere over the rainbow, way up high',
      ),
      Line(
        chords: ['C', 'G', 'Am', 'F'],
        lyric: "And the dreams that you dream of, once in a lullaby",
      ),
      Line(
        chords: ['C', 'G', 'Am', 'F'],
        lyric: 'Somewhere over the rainbow, bluebirds fly',
      ),
      Line(
        chords: ['C', 'G', 'Am', 'F'],
        lyric: "And the dreams that you dare to, oh why oh why can't I",
      ),
    ]),
    Section(
      name: '🎵 接着那段 "What a wonderful world"',
      lines: [
        Line(
          chords: ['C', 'G', 'Am', 'F'],
          lyric: 'Well I see trees of green, red roses too',
        ),
        Line(
          chords: ['C', 'G', 'Am', 'F'],
          lyric: 'I watch them bloom for me and you',
        ),
        Line(
          chords: ['Am', 'F', 'C', 'G'],
          lyric: 'And I think to myself, what a wonderful world',
        ),
      ],
    ),
  ],
);
