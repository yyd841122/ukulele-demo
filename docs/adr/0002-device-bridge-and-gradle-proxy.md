# 手机连接走 Windows adb + WSL 共享 localhost;Gradle 走 VPN 代理需特殊配置

Status: accepted(**§1 手机连接已推翻**——见下方勘误;§2 Gradle/代理仍有效)

## ⚠️ 勘误(2026-08-05,装第28步实测)

**§1「走 Windows adb localhost 桥、不用 usbipd」是错的,别再照这个做。** 实测(第24~28步全用)正解是 **usbipd-win + WSL Linux adb**:
`usbipd bind --busid 5-2`(不用 `--force`)→ `usbipd attach --wsl --busid 5-2` → WSL 的 Linux adb(`~/development/android-sdk/platform-tools/adb`)见到设备 → `flutter run -d AXSC024C07005792`。
- 下面 §决定1 / §为什么第1条 / §后果里「Windows adb / 别用 Linux adb / 重启要先 Windows start-server」**全部作废**。
- 真正的 5037 冲突是「Linux adb 和 Windows adb 同时跑」——usbipd 流程只用 Linux adb,装前 `/mnt/c/platform-tools/adb.exe kill-server` 杀掉 Windows server 即可。
- 今天(2026-08-05)还踩的坑:别手动 `adb push`+`pm install`(用 `flutter run` 一条龙)、别加 `bind --force`(正常 bind 就行)、"设备描述符请求失败"是手机 USB gadget 卡死(切 USB 模式/重启手机即可,**非线坏**)。详见项目记忆 `flutter-android-setup`。

下面原文保留作历史记录。

## 背景
开发环境是 WSL2(mirrored 网络模式)+ 必须常开的 VPN(HTTP 代理 `127.0.0.1:17891` + TUN 全局模式,不能关——Claude 本身也靠它联网)。Flutter/Android SDK 装在 WSL(`~/development/`),手机(荣耀 300)用 USB 插在 Windows 上。

## 决定
1. **手机连接**:不用 usbipd 把 USB 转给 WSL(实测 adb 检测不到 vhci 设备、极不稳)。改为 **adb server 跑在 Windows**(手机原生 USB,可靠),WSL 的 adb 客户端借 **mirrored 模式共享的 localhost(`127.0.0.1:5037`)** 连到 Windows 的 adb server。Windows adb 在 `C:\platform-tools\adb.exe`。
2. **Gradle 构建**:VPN 代理让 Gradle 默认下载卡死(但 curl 走同一代理却 2.7MB/s——问题是 Gradle 的连接管理,不是带宽)。在 `android/gradle.properties` 里显式配代理 + 超时拉到 5 分钟 + 关并行(`org.gradle.parallel=false`)治好。Gradle 本体走腾讯镜像(`gradle-wrapper.properties`),Flutter 引擎走 `storage.googleapis.com`(`FLUTTER_STORAGE_BASE_URL`——因为 `storage.flutter-io.cn` 镜像已坏、返回警告 HTML 页)。

## 为什么
- WSL 直接 USB/adb:usbipd attach 后 adb 对 vhci 设备检测不稳(mirrored 模式尤甚);Windows 原生 adb 最可靠,mirrored localhost 让 WSL 免配置借到。
- Gradle 默认连接方式(多并发/HTTP2)跟 VPN 代理闹别扭;超时+低并发+显式代理对症。

## 后果
- **每次重启电脑后**,要先在 Windows 起一次 adb server(`C:\platform-tools\adb.exe start-server`),WSL 才能连手机。
- **改 VPN 节点/代理端口**,要同步改 `android/gradle.properties` 里的 `proxyPort`(现在是 17891)。
- Flutter SDK 在 WSL `~/development/`;Windows 上只有 `adb`(+ usbipd-win,已不用但留着无妨)。
- **【2026-08-03 新坑】千万别用 WSL 自带的 Linux adb**(`~/development/android-sdk/platform-tools/adb`)做手机相关操作。它会在 WSL 侧起一个 Linux adb server,跟 Windows 的 adb server 抢同一个 `127.0.0.1:5037`(mirrored 模式下两者共享 localhost),表现为 `could not read ok from ADB Server` / `failed to start daemon`,手机怎么插都认不到。**所有 adb 命令一律用 Windows 的 `/mnt/c/platform-tools/adb.exe`。** 万一 server 被搞坏:PowerShell 跑 `Get-Process adb | Stop-Process -Force` 杀干净,再 `/mnt/c/platform-tools/adb.exe start-server` 即可恢复。
