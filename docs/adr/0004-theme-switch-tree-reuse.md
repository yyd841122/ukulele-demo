# 主题切换:ValueNotifier + widget 树复用(换肤不重置 State)

Status: accepted *(第47步,2026-08-07)*

## 背景

app 一直是【仅深色】:`MaterialApp` 只给一个 `theme:`(且 `brightness: Brightness.dark`)。
要做"浅色 / 深色 / 跟随系统"可切换,就得让 `themeMode` 可变、运行时换肤。

换肤有个隐性大坑:`MainScaffold` 的 `_MainScaffoldState` 拥有【共享 `AudioEngine`(嗒声 / 扫弦声源,
启动时 init 了原生 SoLoud)+ `SongStore` + 5 个 tab 的 State(练习页节拍器 `_playing/_idx/_timer`、
统计页、调音页的麦、换和弦页)】。这些 State 是【IndexedStack 保活】攒下来的、贵(音频引擎 init 慢、
节拍器可能正在响)。换肤若让 `home` 被【重建】(给个会变的 key、换 widget 类型,或 setState 重造整棵树),
`_MainScaffoldState` 就 dispose → 音频引擎释放、节拍器中断、各 tab 状态全没——切个主题把练习打断,
不能接受。

## 决定

1. **`ThemeController extends ValueNotifier<ThemeMode>`**(`lib/theme_controller.dart`,新):持有当前
   `ThemeMode`、`init(prefs)` 读回上次选的、`set(mode)` 改值 + 持久化(`pref_theme_mode` =
   system/light/dark)+ notify。默认 `ThemeMode.system`(跟手机)。
2. **`UkuleleApp` 改 `StatefulWidget`**:`ValueListenableBuilder<ThemeMode>` 包 `MaterialApp`,把
   `theme`(浅)/`darkTheme`(深)/`themeMode` 喂进去;mode 一变就重建 `MaterialApp` 换肤。
3. **`home: MainScaffold(theme: controller)`——同一个实例,靠 widget 树复用保 State。**
   `ValueListenableBuilder` 重建 `MaterialApp` 时,Flutter 做【reconciliation】:新旧 `MainScaffold`
   同类型、无 key → 原地更新、`_MainScaffoldState` **不 dispose / 不重建** → 音频引擎、节拍器、
   歌库、各 tab State 全保住。换肤只换主题,不碰练习状态。
4. **从根注入**:`ThemeController` 在 `UkuleleApp` 拥有 → 传 `MainScaffold` → 传 `StatsScreen`
   (切换菜单在这)。跟 `AudioEngine` / `SongStore` 同一套显式 DI 手法(不引 Provider/Riverpod)。
5. **切换入口在统计页顶栏** `PopupMenuButton`(系统 / 浅色 / 深色,`CheckedPopupMenuItem` 当前打勾);
   `StatsScreen` `addListener` 让按钮图标随当前模式刷新。

## 为什么

- **`ValueNotifier` 而非 Provider/Riverpod**:跟 ADR-0003 的 `SongStore` 同理——项目零状态管理依赖,
  `ValueNotifier` + `ValueListenableBuilder` 是 Flutter 内置惯用法,够用。
- **树复用是关键、不是 incidental**:`MaterialApp` 因 `themeMode` 变而重建是必然的;关键是保证它的
  `home` 在重建前后是【同一个 widget 身份】(同类型、key 不变),这样 Flutter 复用 `Element`、保留
  `State`。这层认知不写下来,以后有人"优化"成给 `MainScaffold` 套个会变的 key、或把 `home` 挪进会
  整片重建的父级 → 静默重置音频引擎,极难排查。
- **默认 `system`**:现代 app 的期望(跟手机系统)。app 之前强制深色,改 system 后浅色手机会看到
  浅色——这是"支持深色模式"的本意,不算回退。
- **不归主题管的颜色保持**:`tuner_screen` 的 `Colors.green`(「准」=绿)、`Colors.white`(绿按钮上的字)
  是【状态色 / 语义色】,两套主题都该是绿;和弦图全用 `cs.*` 主题色,自动适配浅色。全库仅 ~8 处硬编码
  颜色、全是语义色,所以浅色模式无需逐一改。

## 考虑过的备选

- **每次换肤 `setState` 重造 `MaterialApp` + `home`**:能换肤,但若不保证 `home` 身份稳定就会丢 State;
  `ValueListenableBuilder` 把"只换 themeMode、home 不动"的意图写明白,更安全。本质都靠树复用,
  选意图更清晰的写法。
- **Provider/Riverpod 注入主题**:更"正统",但新依赖、过度工程;`ValueNotifier` 够。否决。
- **每个 tab 的 AppBar 都放主题开关**:发现性高但散、重复;集中放统计页一个入口够。否决。
- **不持久化(每次启动默认 system)**:用户手动选过的偏好会丢,体验差;持久化到 prefs。否决。

## 后果

- 新增 `lib/theme_controller.dart`;`UkuleleApp` 从 `StatelessWidget` 改 `StatefulWidget`;
  `MainScaffold` / `StatsScreen` 各加一个 `theme` 参数(经根注入)。
- **红线:`MainScaffold` 不能被赋予会变的 `key`、也不能被挪进"因主题变而整片重建"的父级**——
  否则 `home` 的 `Element` 被替换、`_MainScaffoldState` 重置、音频引擎 / 节拍器中断。换肤相关改动
  务必保持 `home` 的 widget 身份稳定。
- 以后再加"全局 UI 偏好"(语言、全局字号等)走同一套:`ValueNotifier` 从根注入 + 树复用。
- 主题模式键 `pref_theme_mode`(system/light/dark);`ThemeController._fromString/_toString` 维护
  字符串 ↔ `ThemeMode` 映射。

## 相关

- 实现:第47步,见 `docs/handover-2026-08-07-step44-47.md`。
- `lib/theme_controller.dart`、`lib/main.dart`(`UkuleleApp` + `ValueListenableBuilder`)、
  `lib/main_scaffold.dart`(注入)、`lib/screens/stats_screen.dart`(切换菜单 + 监听)。
- 状态注入手法承袭 [ADR-0003](0003-song-id-storage.md) 的 `SongStore`(手写 ChangeNotifier/ValueNotifier、
  零新依赖、根注入)。
