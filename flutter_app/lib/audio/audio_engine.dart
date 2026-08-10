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

  // —— 多音色节拍器(第58步-5)——
  // key = 音色名('click'/'beep'/'wood'/'rim'), value = (普通, 重音) 两个 AudioSource。
  // 'click' 桶就是上面的 _normalSrc/_accentSrc(asset wav,默认音色)。
  final Map<String, ({AudioSource normal, AudioSource accent})> _metronomeSounds = {};
  String _currentMetronomeSound = 'click';

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

  // —— 跟唱录音回放(第49步)——
  // 一次性声源槽:回放「听刚才」时 loadMem 录音 WAV 进来 → play;播完或下次回放时释放。单槽位复用,
  // 不堆积、path 不撞 key(每次先 dispose 上一个)。null = 当前没有回放声源占着。
  AudioSource? _voiceSrc;

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
      // 默认音色 'click' 指向 asset wav 桶
      _metronomeSounds['click'] = (normal: _normalSrc!, accent: _accentSrc!);
      _initialized = true;
    } catch (e) {
      // 万一加载失败,这条会进 logcat / 控制台,方便排查。
      debugPrint('音频初始化失败(嗒声): $e');
      return false;
    }
    // 嗒声好了,再尽力预生成扫弦声源(失败只降级,不拖垮嗒声)。
    await _initStrumSources();
    // 第58步-5:尽力预生成另外3种节拍器音色(beep/wood/rim)。失败不影响默认音色。
    await _initMetronomeSounds();
    // 再尽力预生成 4 根空弦参考音(调音页用)。同样失败只降级,不影响前两类声。
    await _initOpenStringSources();
    return true;
  }

  /// 第58步-5:用 StrumSynth 合成 beep/wood/rim 三种节拍器音色,loadMem 进 _metronomeSounds。
  Future<void> _initMetronomeSounds() async {
    for (final style in ['beep', 'wood', 'rim']) {
      try {
        final pair = StrumSynth.synthesizeClickPair(style: style);
        final nSrc = await SoLoud.instance.loadMem('click_${style}_normal', pair.normal);
        final aSrc = await SoLoud.instance.loadMem('click_${style}_accent', pair.accent);
        _metronomeSounds[style] = (normal: nSrc, accent: aSrc);
      } catch (e) {
        debugPrint('节拍器音色 $style 合成失败: $e');
      }
    }
  }

  /// 选节拍器音色(第58步-5)。[name] = 'click'/'beep'/'wood'/'rim'。不在 map 里就退回 click。
  void setMetronomeSound(String name) {
    if (_metronomeSounds.containsKey(name)) _currentMetronomeSound = name;
  }

  /// 当前选的音色名(给持久化 + 界面显示用)
  String get metronomeSound => _currentMetronomeSound;

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

  /// 播一声嗒(第58步-5:按当前选中的音色播)。play(src) 每次起全新实例从头播。
  /// accent=true 播高音重音(第 1 拍),否则普通嗒。引擎没好时 src 为 null,跳过。
  void playClick({bool accent = false}) {
    final pair = _metronomeSounds[_currentMetronomeSound];
    if (pair == null) return;
    final src = accent ? pair.accent : pair.normal;
    SoLoud.instance.play(src);
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

  /// 一次性回放一段完整 WAV 字节(给跟唱录音「听刚才」用)。loadMem 进内存 → play → 估时长后释放声源。
  /// 连续回放:先 dispose 上一次的声源再 load 新的(单槽位复用、path 复用,不堆积、不撞 key)。
  /// 引擎没好 / 加载失败 → 打日志、不崩。fire-and-forget:调用方不必 await。
  Future<void> playWavBytes(Uint8List wav, {double volume = 1.0}) async {
    if (!_initialized) return;
    // 先释放上一次的回放声源(免得连续回放堆一堆一次性声源)。
    final prev = _voiceSrc;
    _voiceSrc = null;
    if (prev != null) {
      try {
        SoLoud.instance.disposeSource(prev);
      } catch (e) {
        debugPrint('释放旧回放声源失败: $e');
      }
    }
    try {
      final src = await SoLoud.instance.loadMem('voice_take', wav);
      _voiceSrc = src;
      SoLoud.instance.play(src, volume: volume);
      // 播完释放:data 字节 = 总长 - 44 头;单声道 16 位 = 每样本 2 字节 → 时长 = 样本数 / 采样率。
      // 采样率跟扫弦同一个 StrumSynth.sampleRate(44100),录音也用这个(见 wavFromPcm16)。
      final samples = (wav.length - 44) ~/ 2;
      final ms = (samples * 1000 / StrumSynth.sampleRate).round();
      Future.delayed(Duration(milliseconds: ms + 300), () {
        if (_voiceSrc == src) _voiceSrc = null; // 这期间没被新回放顶替才清槽
        try {
          SoLoud.instance.disposeSource(src);
        } catch (e) {
          debugPrint('回放声源播完释放失败: $e');
        }
      });
    } catch (e) {
      debugPrint('回放录音失败: $e');
    }
  }

  /// 释放所有声源(嗒声 × 多音色 + 扫弦 × 各移调桶)。页面销毁时调,否则占资源。
  void dispose() {
    // 多音色节拍器:每个音色桶有两个声源,分开 dispose
    for (final pair in _metronomeSounds.values) {
      try { SoLoud.instance.disposeSource(pair.normal); } catch (_) {}
      try { SoLoud.instance.disposeSource(pair.accent); } catch (_) {}
    }
    // _normalSrc/_accentSrc 也在 _metronomeSounds['click'] 里,上面的循环已 dispose 过;
    // 再调 disposeSource 同一个声源会崩(SoLoud 内部断言),所以这里清 null 跳过。
    _normalSrc = null;
    _accentSrc = null;
    for (final bucket in _chordsByOffset.values) {
      for (final s in bucket.values) {
        SoLoud.instance.disposeSource(s.down);
        SoLoud.instance.disposeSource(s.up);
      }
    }
    for (final s in _openStrings.values) {
      SoLoud.instance.disposeSource(s);
    }
    if (_voiceSrc != null) SoLoud.instance.disposeSource(_voiceSrc!);
  }
}
