# 🌈 尤克里里弹唱练习

一个跟着**节拍器**练尤克里里弹唱的安卓 app(Flutter):告诉你现在该按哪个和弦、怎么按、什么时候换、扫几下;还能给琴调音、专项练和弦切换、看练习打卡。

> 跟着 Claude Code 一步步从零做出来的第一个项目(第8步起从 PWA 迁到 Flutter 安卓,做到第58步)。领域词汇见 [CONTEXT.md](CONTEXT.md),架构决策见 [docs/adr/](docs/adr/)。

## 能干啥

**练习**(主 tab)
- 🥁 节拍器:嗒声 + 第1拍重音 + 倒计时预备拍;速度可调(半速~两倍)+ 自动提速(每遍 +3 BPM、到原速停);**4 种音色可选(嗒声/电子嘀/木鱼/鼓边)**
- 🎸 和弦指法图随**当前行**高亮;扫弦节奏型可选(全下 / 下上 / 海岛 / 民谣 / 摇滚),一排 ↓↑ 按节奏高亮
- 🔁 AB 段落循环:点歌词两行标 A/B,反复练那一段
- 📜 歌词自动滚动、字号可调、练琴时屏幕常亮
- 🎚 **移调(虚拟变调夹)**:照旧按原和弦指法,扫弦声整体升/降 ±6 半音贴合嗓音(双向,按歌记)
- 🎙 **跟唱录音**:练琴时录人声,顶栏「听刚才」回放最后一段
- 📊 本次 / 累计遍数 + 时长、整首进度条
- 🔍 **歌曲搜索**:顶栏搜索框按歌名实时筛选
- ⭐ **收藏歌曲**:点心形收藏常用歌,FilterChip 可筛「收藏」
- 🖥 **全屏练习模式**:隐藏顶栏/底导航,沉浸只看歌词+练习栏

**和弦** tab:43 个和弦大图速查(分 9 组:大三/小三/属七/大七/小七/sus4/sus2/dim/aug),点一下听扫弦声。

**统计** tab:总计遍数 / 时长 + 🎯 每日练琴目标(进度条 + 可设目标) + 🔥 连续练琴天数 + 13 周练习日历热力图 + 每首歌明细;顶栏 🎨 可切主题(跟随系统 / 浅色 / 深色);顶栏 ☁ **备份/分享/导入**自加歌(导出 JSON 文本 → 复制或系统分享;粘贴文本导回);🔔 练习提醒(每日定时通知,可调时间)。

**调音** tab:真调音器——听麦克风测拨弦音高 → 指针表显示偏低 / 准 / 偏高 + 选弦判对;A4 校准(430~450Hz);GCEA 空弦参考音;选中的弦调准时按钮变绿、4 根全绿 = 全调好。

**换和弦** tab:挑两个和弦跟着节拍按时切换、数你换了多少次,带「60 秒挑战」;**5 档难度**(自定义/入门4个/初级8个/中级14个/高级43个) + 🎲 随机抽 + 🏆 各难度最佳成绩;记住上次选的弦对 / 速度 / 档位。

**26 首内置歌**(13 英文 + 13 中文) + 你自己加的歌。英文:Somewhere Over the Rainbow、What a Wonderful World、Let It Be、You Are My Sunshine、Riptide、I'm Yours、Stand By Me、Hey Soul Sister、Zombie、Counting Stars、Can't Help Falling in Love、Lean on Me、Blowin' in the Wind、Three Little Birds、Hallelujah、No Woman No Cry、Country Roads。中文:月亮代表我的心、童年、那些花儿、后来、朋友、童话、那些年、小幸运、遇见。支持 3/4 拍(如"遇见")。还能在 app 里**加自己的歌**(选歌下拉框 →「➕ 添加自己的歌」,填歌名 + 速度 + **每和弦几拍(2/3/4/6/8)** + 歌词带和弦;点和弦按钮在光标处插 `[C]`、行首写 `#副歌` 给段落命名),加完跟内置歌一样能跟练、能改、能删。练习页顶栏 **FilterChip** 可筛 全部/英文/中文/**收藏**;🔍 搜索框按歌名找歌;⭐ 点心形收藏常用歌。

## 在安卓手机上用

```bash
cd flutter_app
flutter build apk --release      # → build/app/outputs/flutter-apk/app-release.apk(约 62MB 通用包)
```

把 APK 拷到手机装即可(手机需开「允许未知来源」)。
- **荣耀**:直接 `adb install app-release.apk`。
- **OPPO(ColorOS)**:`adb install` 被挡,走「拷 APK 到手机 → 文件管理器点装」。

## 项目结构

Flutter 工程在 `flutter_app/`。`lib/` 下:`audio/`(音频引擎 / Karplus-Strong 扫弦合成 / 麦克风采集 / YIN 测音高 / 跟唱录音器)、`prefs/`(SharedPreferences 封装)、`screens/`(各 tab 页 + 自加歌表单)、`widgets/`(和弦图 / 歌词 / 练习栏)、`song_store.dart`(歌库:内置歌 + 用户自加歌,ChangeNotifier)、`song_backup.dart`(歌曲备份/导入纯函数)、`theme_controller.dart`(主题模式控制器:系统 / 浅色 / 深色)、`models.dart`(歌曲数据 + 纯函数)。安卓端是空 `FlutterActivity`——纯 Flutter、无自写平台通道。歌曲按稳定 id 存偏好(不按下标,加 / 删用户歌不会串数据),详见 [docs/adr/0003-song-id-storage.md](docs/adr/0003-song-id-storage.md)。
