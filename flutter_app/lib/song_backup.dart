// 歌曲备份 / 导入(第50步):把用户自加的歌序列化成 JSON 文本(备份 / 分享),再能从文本导回。
//
// 纯函数、无副作用(不碰 IO / 不碰 prefs):encodeBackup / decodeBackup 抽出来就是为了能在无头测试里
// 直接锁「导出 → 导入」往返不丢字段。文件 / 分享 / 剪贴板这些 IO 由界面层(stats_screen)负责,
// 这里只管「Song 列表 ↔ JSON 字符串」。
//
// 备份格式:{"app":"ukulele-demo","kind":"song-backup","version":1,"songs":[ Song.toJson, ... ]}。
// 解析尽量宽松:既认这份带壳的 JSON,也认光秃秃一个 [Song,...] 数组(方便手改 / 别处拼的)。
// 内置歌不在备份里(它们在代码里);只备份用户自加歌。导入时一律分配新的 'u<n>' id,不信任备份里的 id
// (免得跟现有用户歌撞 id,或顶到别人的练习记录)。
import 'dart:convert';

import 'models.dart';

/// 备份格式版本(解析时只读、不强制校验,留作以后跨版本兼容用)。
/// v2:加了可选 stats 段(练习打卡日历 + 每日目标),换机 / 重装不丢连续打卡。v1 备份照样能读(没 stats)。
const int kBackupVersion = 2;

/// 把一批歌(调用方传用户自加歌)+ 可选练习统计序列化成备份 JSON 字符串。
/// [stats] 给了就带上(打卡日历 + 每日目标),换机 / 重装能恢复连续打卡;不给就只备份歌。
/// 纯函数、确定性:同样的输入 → 同样的字符串(无时间戳 / 随机),方便测试锁往返。
String encodeBackup(List<Song> songs, {Map<String, dynamic>? stats}) {
  final map = <String, dynamic>{
    'app': 'ukulele-demo',
    'kind': 'song-backup',
    'version': kBackupVersion,
    'songs': [for (final s in songs) s.toJson()],
  };
  if (stats != null) map['stats'] = stats; // 给了才带(换机 / 重装恢复连续打卡);不给就只备份歌
  return jsonEncode(map);
}

/// 把备份 JSON 文本解析回 Song 列表。
/// 认两种形态:{"songs":[...]} 带壳备份,或光秃秃 [...] 数组。不是合法 JSON / 没有 songs → 抛 FormatException。
/// 单首歌用 Song.fromJson 解(它对缺字段给默认值,跨版本向前兼容)。
/// 数组里任何非对象元素 → 立刻抛 FormatException 告知用户(不静默丢歌,宁可拒收也不让用户以为全导入成功了)。
List<Song> decodeBackup(String text) {
  final Object decoded;
  try {
    decoded = jsonDecode(text.trim());
  } on FormatException {
    throw const FormatException('不是合法的 JSON,检查是不是粘全了');
  }
  List<Object?> raw;
  if (decoded is List) {
    raw = decoded; // 光秃秃数组也认
  } else if (decoded is Map && decoded['songs'] is List) {
    raw = decoded['songs'] as List;
  } else {
    throw const FormatException('不是有效的歌曲备份(缺 songs 字段)');
  }
  final songs = <Song>[];
  for (final s in raw) {
    if (s is Map<String, dynamic>) {
      songs.add(Song.fromJson(s));
    } else {
      throw const FormatException('备份里有不是歌曲的数据,检查格式');
    }
  }
  return songs;
}

/// 解出备份里的练习统计段(打卡日历 + 每日目标)。没有(旧 v1 备份、裸数组、或没传 stats)→ null。
/// 解析失败也不抛(调用方按 null 处理 = 不动现有统计);只有合法的带壳 JSON 且带 stats 才返回。
Map<String, dynamic>? decodeStats(String text) {
  try {
    final decoded = jsonDecode(text.trim());
    if (decoded is Map && decoded['stats'] is Map) {
      return (decoded['stats'] as Map).cast<String, dynamic>();
    }
  } catch (_) {
    // 非法 JSON / 不是对象:按没 stats 处理(decodeBackup 那边会负责报错给用户)。
  }
  return null;
}
