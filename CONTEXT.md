# 尤克里里弹唱练习 (Ukulele Strum-and-Sing Practice)

一个跟着节拍器练习尤克里里弹唱的练习器:告诉你现在该按哪个和弦、怎么按、什么时候换、扫几下。
本文件是这套 app 的**领域词汇表**——只统一概念叫法,不写代码实现,也不写决策(决策在 `docs/adr/`)。

## 语言 (Language)

**Song(歌曲)**:
一首可练习的曲子。包含标题、速度(tempo)、每个和弦持续几拍(beatsPerChord)、若干 Section。
_Avoid_: track, music

**Section(段落)**:
一首歌里有名字的小节,如"副歌"、那段 "What a wonderful world"。由若干 Line 组成。
_Avoid_: part, block

**Line(歌词行)**:
一行歌词,以及压在它上方、按顺序排列的 Chord。
_Avoid_: row("行"会和表格行混,统一叫 Line)

**Chord(和弦)**:
某个时刻要按下的和声,有名字(如 C、G、Am、F)和指法。
_Avoid_: harmony

**Chord Diagram(和弦指法图)**:
画出来的小图,告诉你这个 Chord 的四根弦分别按第几品。
_Avoid_: fingering chart

**Fret(品)**:
琴颈上的横格,从琴头方向数 1、2、3……;0 = 空弦(不按)。

**String(弦)**:
尤克里里的四根弦,从左到右约定为 **G C E A**。代码里 `frets` 数组就按这个顺序。

**Beat(拍)**:
节拍器的一下"嗒"。`beatsPerChord` = 一个 Chord 持续几拍后换下一个。

**Strum(扫弦)**:
一下向下的扫。界面用一排 ↓ 表示,每个 Beat 一个,高亮当前那下。
_Avoid_: stroke

**Tempo / BPM(速度)**:
每分钟多少拍,决定节拍器快慢。

**Metronome click(节拍声)**:
每个 Beat 合成出来的"嗒"声;每小节第 1 拍是重音(音调更高)。
