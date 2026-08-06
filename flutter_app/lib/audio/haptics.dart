// 震动反馈:Dart 端入口,通过平台通道调安卓 Vibrator 马达。
//
// 为什么自己写、不引第三方包:
//   - HapticFeedback(view.performHapticFeedback)走系统"触感反馈"通道,被 ColorOS 等 OEM 的
//     设置 / 省电压掉(实测调音准了不震)。
//   - vibration 包能用,但会拉一个原生插件进 Gradle,release 构建又慢又容易因 R8 / SDK 摩擦挂。
// 自己几行 Kotlin(见 MainActivity)搞定:同样要 VIBRATE 权限(已声明)、同样直接驱动马达、
// 不受系统触感开关影响,且不增加构建负担。
import 'package:flutter/services.dart';

class Haptics {
  // 平台通道名(要跟 MainActivity 里的 "ukulele_demo/haptics" 完全一致)。全局复用一份。
  static const _channel = MethodChannel('ukulele_demo/haptics');

  /// 震一下马达,[durationMs] 毫秒(默认 30,短促一"哒")。
  /// 调用失败(平台没接好 / 无马达 / 无头测试环境)静默忽略——震动是锦上添花,
  /// 绝不该让调音因为震不动而崩或卡。
  static Future<void> buzz([int durationMs = 30]) async {
    try {
      await _channel.invokeMethod('vibrate', durationMs);
    } on PlatformException {
      // 平台异常(通道没注册等)→ 忽略。
    } on MissingPluginException {
      // 通道还没接上(如无头测试环境)→ 忽略。
    }
  }
}
