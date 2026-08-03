// 尤克里里弹唱练习 —— 数据模型。
//
// 概念叫法统一见仓库根目录 CONTEXT.md:
//   Song(歌曲) → Section(段落) → Line(歌词行) → Chord(和弦)
//
// 这个文件【只放数据长什么样】,不放界面。界面在 main.dart。
// 加新歌只是往下面的 songs 列表里再加一条,界面自动跟上。
import 'package:flutter/foundation.dart';

/// 一行歌词 + 压在它上方的和弦序列(按出现顺序)。
/// 例如 chords: ["C","G","Am","F"]  lyric: "Somewhere over the rainbow..."
@immutable
class Line {
  final List<String> chords;
  final String lyric;

  const Line({required this.chords, required this.lyric});
}

/// 歌曲里的一个段落,例如"副歌"。name 可空 —— 单段落的歌常没有名字。
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

/// 歌曲库。界面里用顶栏下拉框选一首。
///
/// 数据照搬 Web 版(index.html 的 SONGS)。原 IZ 版把《Over the Rainbow》和
/// 《What a Wonderful World》串成一首串烧(medley),这里按"两首就该分两条"的
/// 原则拆成两首,免得新手以为后半段是《Over the Rainbow》的词。
const List<Song> songs = [
  Song(
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
    ],
  ),
  Song(
    title: '🌻 What a Wonderful World',
    tempo: 70,
    beatsPerChord: 4,
    sections: [
      Section(lines: [
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
      ]),
    ],
  ),
];
