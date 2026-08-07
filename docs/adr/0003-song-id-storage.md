# 歌曲按稳定 id 存偏好(+ SongStore 拥有合并歌单 + 用户自加歌持久化)

Status: accepted *(第43a步,2026-08-07)*

## 背景

每首歌的练习偏好——上次速度(tempo)、AB 循环区间、累计遍数(loops)、累计秒数(sec)——
一直按【歌曲在列表里的下标】存:`getTempo(songIndex)` → 键 `pref_tempo_<下标>`。练习页
(`SongScreen`)和统计页(`StatsScreen`)都按下标遍历顶层 `songs`。

要做"用户自加歌"(加 / 改 / 删),就得让歌曲列表可变。可一旦加 / 删,下标就挪位:

- 删掉第 3 首,原来第 4 首变成第 3 首 → 它读到的 `pref_loops_3` 其实是已删那首的遍数。
- "这首歌练了多少遍"会错位串到别的歌上。

下标是【位置】,不是【身份】;身份不稳定,按身份存的偏好就会乱。

## 决定

1. **给 `Song` 加稳定 `id`(String)。** 所有 per-song 偏好改按 id 存:`getTempo(songId)`。
2. **内置歌的 id = 它下标的字符串**('0'、'1'…… '12')。于是键 `pref_tempo_0` ↔ id `'0'`,
   跟旧版按下标存**一字不差 → 旧练习数据零迁移、原样读得到**。
3. **用户自加歌 id = 'u1'、'u2'……**(单调递增计数器,删了不复用)。内置 id 不以 `u` 开头,
   `isUserSong(s) = s.id.startsWith('u')` 泾渭分明。
4. **引入 `SongStore`(ChangeNotifier)** 统一拥有【内置歌 + 用户自加歌】合并列表;用户歌以
   JSON 字符串列表持久化到 prefs;`add / update / remove` 改列表 → 落盘 → `notifyListeners`。
   练习页下拉框、统计页按歌列表都 `addListener`,歌单一变就刷新。
5. 用户歌的 `id` 存在它自己的 JSON 里 → 跨 app 重启 id 不变 → 它的练习记录(按 id 存)接得上、不丢。

## 为什么

- **按下标的根病是身份不稳**:加 / 删改变列表 → 下标身份漂移。用稳定 id 把"身份"和"位置"解耦。
- **零迁移是个讨巧点,不是偷懒**:内置歌 id 取下标字符串,新旧 pref 键天然一致,免写迁移代码、
  免数据风险。用户的累计遍数 / 秒数一点没丢——这比"用语义 slug 当 id + 写一次性迁移脚本"更简单、
  更安全。内置歌极少重排(只在末尾追加),所以"id = 下标"的脆弱性不会真暴露。
- **SongStore 用 ChangeNotifier(手写,不引 Provider/Riverpod)**:加 / 删歌后两个页面都要刷新,
  ChangeNotifier 是 Flutter 内置惯用法、零新依赖,够用。
- **用户歌 id 单调递增、删了不复用**:删掉 'u2' 后,下一首新歌叫 'u3' 而不是顶上 'u2'——
  即使 `clearSong` 清了旧 key,不复用也多一道保险,不会让新歌撞到旧歌残留的任何状态。

## 考虑过的备选

- **按下标 + 用户歌自带状态**(把 tempo/loops/sec 塞进用户歌的 JSON,内置歌仍按下标):
  内置歌零改动,但 `SongScreen` 每处 per-song 读写都要分支(内置 vs 用户),散布十几处的分支
  又乱又易错;否决。
- **语义 slug 当 id + 迁移旧数据**('rainbow'、'let-it-be'…… + 一次性把 `pref_tempo_0` 搬到
  `pref_tempo_rainbow`):更抗内置歌重排,但要写迁移代码、迁移本身有风险;内置歌极少重排,
  收益不抵成本;否决。
- **引入 Provider / Riverpod 管 SongStore**:更"正统"的状态管理,但项目本来无此依赖,手写
  ChangeNotifier + `addListener` 完全够用;否决,保持零新依赖。
- **用一个 JSON 文件存用户歌**(走 `path_provider`):比 prefs 的字符串列表"正经",但多一个
  依赖、多一层文件 I/O;用户歌就几首、prefs 完全 hold 得住;否决。

## 后果

- per-song 偏好键:`pref_tempo_<int>` → `pref_tempo_<id>`。内置 id = 数字字符串(键不变);
  用户 id = 'u<n>'。`AppPreferences` 所有 per-song 方法首参从 `int songIndex` 改 `String songId`。
- `SongScreen` / `StatsScreen` 多一层 `SongStore` 依赖(经 `MainScaffold` 注入,跟 `AudioEngine` 并列),
  不再直接读顶层 `songs`;各自 `songs` getter 转发到 `widget.store.songs`,旧代码 `songs[...]` 不用改。
- 用户歌存 JSON(`pref_user_songs`,每首一条) + id 计数器(`pref_user_song_seq`)。
  以后改 `Song` 结构要兼顾向后兼容:`Song.fromJson` 对缺失字段给默认值,旧版存的用户歌不会挂。
- **别再把 per-song 偏好改回按下标存**——会重新引入"加 / 删歌串数据"的 bug。这条是本 ADR 的红线。
- 已知小限制(接受):`getSongIndex`(全局"上次选的歌")仍按下标存;若上次选的是用户歌、之后又
  增删了用户歌,重启可能不精确恢复到那首(下标挪了)。低影响,要稳可后续也改按 id 存。

## 相关

- 实现:第43a(重构·id 化)、43b(歌库 + 表单 + 添加)、43c(编辑 + 删除)步,见
  `docs/handover-2026-08-07-step39-43.md`。
- `lib/song_store.dart`、`lib/screens/add_song_screen.dart`、`lib/models.dart`(Song.id / toJson / fromJson)、
  `lib/prefs/app_preferences.dart`(per-song 改 id + getUserSongs / clearSong)。
