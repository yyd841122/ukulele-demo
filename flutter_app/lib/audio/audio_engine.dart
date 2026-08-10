// 音频引擎:统一管 SoLoud(初始化、加载声源、播放、释放)。
// 从 main.dart 拆出(第19步重构)——把原来散在 _SongScreenState 里的音频代码收拢成一个对象,
// SongScreen 只持有它的引用、调它的方法,不再直接碰 SoLoud。
//
// 管三类声源:
//   - 两个嗒声(普通 / 重音)——节拍器用,加载 assets/click*.wav。
//   - 扫弦声源——给每个和弦(×下扫/上扫)用 Karplus-Strong 现场合成出 WAV、loadMem 进内存,
//     要播某个和弦的扫弦时直接 play 对应声源(低延迟、可连发)。
//   - 空弦参考音——4 根空弦(G/C/E/A)各拨一段单音,给调音页做基准(同一个合成引擎,只拨一根)。
import 'package:flutter/foundation.dart'; // debugPrint
import 'package:flutter_soloud/flutter_soloud.dart';

import '../models.dart'; // chordShapes:要知道每个和弦怎么按,才能合成出它的声音
import 'strum_synth.dart';

/// 一个和弦预生成的两个方向扫弦声源(下扫 / 上扫)。
typedef ChordSamples = ({AudioSource down, AudioSource up});

class AudioEngine {
  // —— 嗒声(节拍器)——
  // 把两个嗒声各加载成一个"声源(AudioSource)"。每拍 play(src) 起一个全新实例从头播 →
  // 低延迟、每次从头响、连播不会变小声、第一拍也不会被吞(专为这种场景设计)。
  AudioSource? _normalSrc; // 普通"嗒"
  AudioSource? _accentSrc; // 高音重音

  // —— 扫弦声源(按和弦名 × 移调偏移取)——
  // 启动时给 chordShapes 里每个和弦 × 2 方向各合成一段 WAV、loadMem 进内存,放【0 偏移】那一桶。
  // 播放时按 (和弦名, 当前移调偏移) 查出来 play。没在里面的(没录指法的和弦)→ playChord 跳过、不崩。
  //
  // 第48步(移调·虚拟变调夹):移调偏移 ≠ 0 的声源按需预生成(prepareTranspose)、单独放一桶。
  // 外层的 key = 半音偏移(0 = 不移调;+2 = 升 2 半音……)。和弦速查 / 换和弦 tab 只用 0 桶(原音高),
  // 练习 tab 按当前歌的移调取对应桶——同一引擎、各 tab 各取所需,互不污染。
  final Map<int, Map<String, ChordSamples>> _chordsByOffset = {};
  // 正在后台生成某偏移桶的标记:免得同偏移被并发重复生成。
  final Set<int> _preparing = {};

  // —— 空弦参考音(调音用)——
  // 启动时给 4 根空弦(G/C/E/A)各合成一段单音拨弦、loadMem 进内存。调音页点某根弦 → play 对应声源。
  // 复用扫弦同款 Karplus-Strong 合成(StrumSynth),只是拨一根而不是扫四根。
  final Map<int, AudioSource> _openStrings = {};

  /// 调音参考音持续多久(秒)。比扫弦(0.8s)长——调音要边听边拧弦钮,余音长点好对音。
  static const double referenceToneSec = 2.5;

  bool _initialized = false;

  /// 初始化 SoLoud 引擎、加载嗒声 + 预生成所有和弦的扫弦声源。嗒声好了就返回 true。
  /// 扫弦声源是【尽力而为】:合成 / loadMem 万一失败只打日志、不影响嗒声(降级成纯节拍器)。
  /// 整个嗒声加载失败(如测试环境加载不了原生库)返回 false——调用方据此不点亮 ▶。
  Future<bool> init() async {
    try {
      await SoLoud.instance.init();
      _normalSrc = await SoLoud.instance.loadAsset('assets/click.wav');
      _accentSrc = await SoLoud.instance.loadAsset('assets/click_accent.wav');
      _initialized = true;
    } catch (e) {
      // 万一加载失败,这条会进 logcat / 控制台,方便排查。
      debugPrint('音频初始化失败(嗒声): $e');
      return false;
    }
    // 嗒声好了,再尽力预生成扫弦声源(失败只降级,不拖垮嗒声)。
    await _initStrumSources();
    // 再尽力预生成 4 根空弦参考音(调音页用)。同样失败只降级,不影响前两类声。
    await _initOpenStringSources();
    return true;
  }

  /// 给 chordShapes 里每个和弦合成下扫 / 上扫两段 WAV,loadMem 进【0 偏移】桶(原音高)。
  Future<void> _initStrumSources() async {
    try {
      _chordsByOffset[0] = await _buildStrumSources(0);
    } catch (e) {
      debugPrint('扫弦声源预生成失败(嗒声仍可用): $e');
    }
  }

  /// 合成某个移调偏移下、chordShapes 里每个和弦的下扫 / 上扫声源,返回「和弦名 → 两方向声源」。
  /// [semitoneOffset] = 0 是原音高(启动时建);≠ 0 给移调用(prepareTranspose 按需建)。
  /// 同一个和弦指法,偏移不同 → 合成出的频率不同 → 听上去是移调后的扫弦。path 带偏移前缀防撞 key。
  Future<Map<String, ChordSamples>> _buildStrumSources(int semitoneOffset) async {
    final synth = StrumSynth(); // 不传 seed → 每次随机起振,更像真琴
    final out = <String, ChordSamples>{};
    final prefix = semitoneOffset == 0 ? '' : '${semitoneOffset}_';
    for (final entry in chordShapes.entries) {
      final name = entry.key;
      final frets = entry.value;
      final down = await SoLoud.instance.loadMem(
        '${prefix}strum_${name}_down', // path 要唯一(同名会撞);偏移前缀 + 和弦名×方向天然唯一
        synth.synthesizeStrumWav(frets, semitoneOffset: semitoneOffset),
        // mode 默认 LoadMode.memory:解压进内存、低延迟,适合反复快速播。
      );
      final up = await SoLoud.instance.loadMem(
        '${prefix}strum_${name}_up',
        synth.synthesizeStrumWav(frets, up: true, semitoneOffset: semitoneOffset),
      );
      out[name] = (down: down, up: up);
    }
    return out;
  }

  /// 预生成某个移调偏移的声源桶(给练习页设了移调后调,提前建好、播放时不卡顿)。
  /// 0 桶启动时就有;已建过 / 正在建的偏移直接返回;引擎没好(如测试环境)也直接返回。
  /// fire-and-forget:调用方不必 await——没建好期间 playChord 会回退到 0 桶(原音高)兜底,不静音。
  Future<void> prepareTranspose(int semitoneOffset) async {
    if (semitoneOffset == 0) return; // 0 桶启动时就建好了
    if (_chordsByOffset.containsKey(semitoneOffset)) return; // 已建过
    if (_preparing.contains(semitoneOffset)) return; // 正在建
    if (!_initialized) return; // 引擎没好(测试环境),不建
    _preparing.add(semitoneOffset);
    try {
      _chordsByOffset[semitoneOffset] = await _buildStrumSources(semitoneOffset);
    } catch (e) {
      debugPrint('移调声源预生成失败(偏移 $semitoneOffset): $e');
    } finally {
      _preparing.remove(semitoneOffset);
    }
  }

  /// 给 4 根空弦各合成一段拨弦参考音、loadMem 进内存。跟扫弦一样【尽力而为】:
  /// 失败只打日志、不影响嗒声 / 扫弦。固定种子:参考音是基准,每次都一样(不跟扫弦那样随机起振)。
  Future<void> _initOpenStringSources() async {
    try {
      final synth = StrumSynth(seed: 20240801); // 固定种子 → 参考音稳定可复现
      for (var i = 0; i < StrumSynth.openTuning.length; i++) {
        final src = await SoLoud.instance.loadMem(
          'open_string_$i', // path 要唯一,弦下标天然唯一
          synth.synthesizeOpenStringWav(i, durationSec: referenceToneSec),
        );
        _openStrings[i] = src;
      }
    } catch (e) {
      debugPrint('空弦参考音预生成失败(嗒声 / 扫弦仍可用): $e');
    }
  }

  /// 引擎和嗒声都加载好了吗(没好之前 ▶ 按钮变灰、按了也不出声)。
  bool get isReady => _initialized;

  /// 播一声嗒。play(src) 每次起一个全新实例从头播 → 低延迟、每次从头响、连播不会变小声。
  /// accent=true 播高音重音(第 1 拍),否则普通嗒。引擎还没加载好时 src 为 null,跳过。
  void playClick({bool accent = false}) {
    final src = accent ? _accentSrc : _normalSrc;
    if (src != null) SoLoud.instance.play(src);
  }

  /// 播某个和弦的扫弦声。up=false 下扫、up=true 上扫。[semis] = 移调偏移(0 = 原音高)。
  /// 取声源顺序:先找【当前偏移】桶,没有(还没 prepare 好)就回退到【0 桶】原音高兜底——
  /// 这样刚设移调、声源还在后台生成的那一小段不会静音(顶多短暂是原音高,生成完就准了)。
  /// 两桶都没这个和弦(没录指法)就跳过 + 打日志。多声部:每次 play 起新实例从头播,连发 / 叠着不互相影响。
  void playChord(String chord, {bool up = false, double volume = 0.9, int semis = 0}) {
    final s = (_chordsByOffset[semis] ?? _chordsByOffset[0])?[chord];
    if (s == null) {
      debugPrint('扫弦:没有「$chord」的声源(没录指法?),跳过');
      return;
    }
    SoLoud.instance.play(up ? s.up : s.down, volume: volume);
  }

  /// 播第 stringIndex 根空弦(G=0 / C=1 / E=2 / A=3)的参考音,给调音页用。
  /// 没预生成好(初始化失败)就跳过 + 打日志。每次 play 起一个新声部从头播,连点不互相影响。
  void playOpenString(int stringIndex, {double volume = 0.9}) {
    final src = _openStrings[stringIndex];
    if (src == null) {
      debugPrint('参考音:第 $stringIndex 弦没预生成(初始化失败?),跳过');
      return;
    }
    SoLoud.instance.play(src, volume: volume);
  }

  /// 释放所有声源(嗒声 + 扫弦 × 各移调桶)。页面销毁时调,否则占资源。
  void dispose() {
    if (_normalSrc != null) SoLoud.instance.disposeSource(_normalSrc!);
    if (_accentSrc != null) SoLoud.instance.disposeSource(_accentSrc!);
    for (final bucket in _chordsByOffset.values) {
      for (final s in bucket.values) {
        SoLoud.instance.disposeSource(s.down);
        SoLoud.instance.disposeSource(s.up);
      }
    }
    for (final s in _openStrings.values) {
      SoLoud.instance.disposeSource(s);
    }
  }
}
