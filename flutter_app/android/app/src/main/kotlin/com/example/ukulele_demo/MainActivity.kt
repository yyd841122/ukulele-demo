package com.example.ukulele_demo

import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// 调音"准了"震动:听 Dart 端 Haptics.buzz() 通过平台通道发来的 vibrate 调用,直接驱动 Vibrator 马达。
//
// 为什么自己写、不引第三方包:
//   - HapticFeedback(view.performHapticFeedback)走系统"触感反馈"通道,被 ColorOS 等 OEM 的
//     设置 / 省电压掉(实测调音准了不震)。
//   - vibration 包能用,但会拉一个原生插件进 Gradle,release 构建又慢又容易因 R8 / SDK 摩擦挂。
// 自己几行 Kotlin 搞定:同样要 VIBRATE 权限(AndroidManifest 已声明)、同样直接驱动马达、
// 不受系统触感开关影响,且不增加构建负担。
class MainActivity : FlutterActivity() {
    // 通道名:要跟 Dart 端 Haptics 里的 "ukulele_demo/haptics" 完全一致。
    private val channel = "ukulele_demo/haptics"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                if (call.method == "vibrate") {
                    // Dart 端 invokeMethod("vibrate", durationMs) 把毫秒数当单个参数传过来。
                    val durationMs = (call.arguments as? Number)?.toLong() ?: 30L
                    buzz(durationMs)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }

    // 震一下马达(毫秒)。API 26+ 用 VibrationEffect;minSdk=24,所以 24/25 走老的 vibrate(Long) 兼容分支。
    private fun buzz(durationMs: Long) {
        @Suppress("DEPRECATION") // getSystemService(VIBRATOR_SERVICE) 在 API 31+ 标弃用,但仍能用。
        val vib = getSystemService(VIBRATOR_SERVICE) as? Vibrator ?: return
        if (!vib.hasVibrator()) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vib.vibrate(VibrationEffect.createOneShot(durationMs, VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            @Suppress("DEPRECATION") // vibrate(Long) 在 API 26+ 标弃用,这里只给 24/25 用。
            vib.vibrate(durationMs)
        }
    }
}
