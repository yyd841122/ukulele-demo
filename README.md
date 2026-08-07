# 🌈 尤克里里弹唱练习

一个跟着**节拍器**练尤克里里弹唱的安卓 app(Flutter):告诉你现在该按哪个和弦、怎么按、什么时候换、扫几下;还能给琴调音、专项练和弦切换、看练习打卡。

> 跟着 Claude Code 一步步从零做出来的第一个项目(第8步起从 PWA 迁到 Flutter 安卓,做到第43步)。领域词汇见 [CONTEXT.md](CONTEXT.md),架构决策见 [docs/adr/](docs/adr/)。

## 能干啥

**练习**(主 tab)
- 🥁 节拍器:嗒声 + 第1拍重音 + 倒计时预备拍;速度可调(半速~两倍)+ 自动提速(每遍 +3 BPM、到原速停)
- 🎸 和弦指法图随**当前行**高亮;扫弦节奏型可选(全下 / 下上 / 海岛 / 民谣 / 摇滚),一排 ↓↑ 按节奏高亮
- 🔁 AB 段落循环:点歌词两行标 A/B,反复练那一段
- 📜 歌词自动滚动、字号可调、练琴时屏幕常亮
- 📊 本次 / 累计遍数 + 时长、整首进度条

**和弦** tab:全部和弦大图速查,点一下听扫弦声。

**统计** tab:总计遍数 / 时长 + 🔥 连续练琴天数 + 13 周练习日历热力图 + 每首歌明细。

**调音** tab:真调音器——听麦克风测拨弦音高 → 指针表显示偏低 / 准 / 偏高 + 选弦判对;A4 校准(430~450Hz);GCEA 空弦参考音;选中的弦调准时按钮变绿、4 根全绿 = 全调好。

**换和弦** tab:挑两个和弦跟着节拍按时切换、数你换了多少次,带「60 秒挑战」;记住上次选的弦对 / 速度 / 档位。

**13 首内置歌** + 你自己加的歌。内置:Somewhere Over the Rainbow、What a Wonderful World、Let It Be、You Are My Sunshine、Riptide、I'm Yours、Stand By Me、Hey Soul Sister、Zombie、Counting Stars、Can't Help Falling in Love、Lean on Me、Blowin' in the Wind。还能在 app 里**加自己的歌**(选歌下拉框 →「➕ 添加自己的歌」,填歌名 + 速度 + 歌词带和弦,点和弦按钮在光标处插 `[C]`),加完跟内置歌一样能跟练、能改、能删。

## 在安卓手机上用

```bash
cd flutter_app
flutter build apk --release      # → build/app/outputs/flutter-apk/app-release.apk(约 62MB 通用包)
```

把 APK 拷到手机装即可(手机需开「允许未知来源」)。
- **荣耀**:直接 `adb install app-release.apk`。
- **OPPO(ColorOS)**:`adb install` 被挡,走「拷 APK 到手机 → 文件管理器点装」。

## 项目结构

Flutter 工程在 `flutter_app/`。`lib/` 下:`audio/`(音频引擎 / Karplus-Strong 扫弦合成 / 麦克风采集 / YIN 测音高)、`prefs/`(SharedPreferences 封装)、`screens/`(各 tab 页 + 自加歌表单)、`widgets/`(和弦图 / 歌词 / 练习栏)、`song_store.dart`(歌库:内置歌 + 用户自加歌,ChangeNotifier)、`models.dart`(歌曲数据 + 纯函数)。安卓端是空 `FlutterActivity`——纯 Flutter、无自写平台通道。歌曲按稳定 id 存偏好(不按下标,加 / 删用户歌不会串数据),详见 [docs/adr/0003-song-id-storage.md](docs/adr/0003-song-id-storage.md)。
