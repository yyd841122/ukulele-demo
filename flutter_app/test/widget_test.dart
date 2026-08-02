// 烟雾测试(smoke test):确认歌曲页能正常构建、并把关键内容渲染出来。
// 这一步不连手机也能跑(flutter test),是"代码真能跑"的快速证据。
import 'package:flutter_test/flutter_test.dart';

import 'package:ukulele_demo/main.dart';

void main() {
  testWidgets('歌曲页能渲染出标题、和弦贴片、歌词', (tester) async {
    // 把整个 app 构建出来。如果代码有构建期错误,这一行就会抛。
    await tester.pumpWidget(const UkuleleApp());

    // 歌曲标题在(AppBar 里)
    expect(find.textContaining('Somewhere Over the Rainbow'), findsOneWidget);

    // 和弦贴片渲染出来了(Am 在这首歌里出现过多次)
    expect(find.text('Am'), findsWidgets);

    // 第一句歌词在
    expect(find.textContaining('way up high'), findsOneWidget);
  });
}
