// 练习提醒(第58步-4):用 flutter_local_notifications 每天定时推送"该练琴了"。
//
// 负责:
//   - 初始化通知插件(Android 通知渠道)
//   - 在 app 启动时按用户偏好设置 / 取消定时通知
//   - 在统计页改了提醒设置后调 sync 更新
//
// 注意:Android 13+ 第一次展示通知时会弹出 POST_NOTIFICATIONS 权限请求(系统级),
// 用户拒绝后通知会静默失败,不会崩 app。
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

import '../prefs/app_preferences.dart';

class ReminderService {
  static final ReminderService _instance = ReminderService._();
  factory ReminderService() => _instance;
  ReminderService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  // 缓存上一次设置,避免每次切到统计 tab 重建卡时重新排通知。
  bool _lastEnabled = false;
  int _lastHour = 19;
  int _lastMinute = 0;

  /// 初始化通知插件:建 Android 渠道 + 加载时区数据。app 启动时调一次。
  /// 包 try/catch:插件未接好的环境(如 headless 测试)抛 MissingPluginException 会冒泡到
  /// UkuleleApp.initState 红屏——跟 MicCapture/VoiceRecorder 同类调用一样兜住。
  Future<void> init() async {
    if (_initialized) return;
    try {
      tz.initializeTimeZones();
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      await _plugin.initialize(
        settings: const InitializationSettings(android: android),
      );
      _initialized = true;
    } catch (_) {
      // 初始化失败:sync 时会再试;不崩 app。
    }
  }

  /// 按用户偏好同步提醒:开了就设每日定时,关了就取消。统计页改设置后调这里。
  Future<void> sync(AppPreferences p, {bool force = false}) async {
    if (!_initialized) await init();
    final enabled = p.getReminderEnabled();
    final hour = p.getReminderHour(19);
    final minute = p.getReminderMinute(0);
    // 没变就不要重排:避免来回切 tab 时无效操作。
    if (!force && enabled == _lastEnabled && hour == _lastHour && minute == _lastMinute) return;
    _lastEnabled = enabled;
    _lastHour = hour;
    _lastMinute = minute;
    await _plugin.cancelAll();
    if (!enabled) return;
    await _scheduleDaily(hour, minute);
  }

  /// 设一个每日定点通知。用 zonedSchedule:时区感知,不会因为时区漂移。
  /// Android 用 alarmClock 模式:高优先级、省电模式也能准时到。
  Future<void> _scheduleDaily(int hour, int minute) async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    await _plugin.zonedSchedule(
      id: 0,
      title: '尤克里里弹唱练习',
      body: '🎸 到练琴时间啦',
      scheduledDate: scheduled,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'practice_reminder',
          '练习提醒',
          channelDescription: '每天提醒该练尤克里里啦',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.alarmClock,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  /// 请求 Android 13+ 的通知权限。返回是否已授权——调用方据此决定开关要不要回滚
  /// (旧版返回 void 丢了结果,用户拒了权限开关还亮着、通知永远不响)。
  Future<bool> requestPermission() async {
    final granted = await _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    return granted ?? false;
  }
}
