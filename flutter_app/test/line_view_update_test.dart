// 回归测试:换歌后歌词不刷新的 bug。
//
// 根因:LineView 是 StatefulWidget(第55步把 parseWords 缓存进 State,免得播放时每半拍重解析),
// 但缓存用 late final 只算一次。而 LineView 本身没 key —— 它的 lineKey 只挂到内部 Container 上、
// 不是 Widget.key。所以 SongScreen 换歌时,Flutter 按位置 reconcile、复用同一行的 _LineViewState,
// 旧歌词的 _units 被沿用 → 换歌后歌词还停在上一首。
//
// 修法:didUpdateWidget 里按 lyric 变了重解析。这个测试直接复现「同一行的 LineView 被复用、
// line 换成新歌的」这条路径(StatefulBuilder 控制 rebuild),断言词跟着换了。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ukulele_demo/models.dart';
import 'package:ukulele_demo/widgets/lyric_view.dart';

void main() {
  testWidgets('换 line 后歌词跟着更新(State 被复用、无 key 的真实路径)', (tester) async {
    // 两首歌的「同一行」:都只有一个和弦词,词不同。模拟换歌时同一槽位接到新歌的 Line。
    var line = const Line(lyric: '[C]HelloFirstSong');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return LineView(
                line: line,
                lineKey: GlobalKey(),
                isCurrentLine: false,
                chordStart: 0,
                currentChord: -1,
                onTap: () => setState(() => line = const Line(lyric: '[G]GoodbyeNextSong')),
              );
            },
          ),
        ),
      ),
    );

    // 起初:第一首歌的词在
    expect(find.textContaining('HelloFirstSong'), findsOneWidget);
    expect(find.textContaining('GoodbyeNextSong'), findsNothing);

    // 触发 rebuild:换 line 到第二首歌(点一下走 onTap → setState → 同一个 LineView 被复用)
    await tester.tap(find.byType(LineView));
    await tester.pumpAndSettle();

    // 关键:词必须跟着换。没修之前这里会失败——还是 HelloFirstSong(late final 缓存没刷新)。
    expect(find.textContaining('GoodbyeNextSong'), findsOneWidget);
    expect(find.textContaining('HelloFirstSong'), findsNothing);
  });
}
