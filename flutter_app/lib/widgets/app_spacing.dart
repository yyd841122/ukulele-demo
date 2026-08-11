// 设计令牌:间距 + 圆角常量。
//
// 背景:各页面原本散写魔法数字(BorderRadius.circular(10/12/16)、SizedBox(height: 8/12/16)…),
// 没有统一出处。新增 / 改动的页面(首页、练琴 Hub、和弦页等)优先用这里的常量,
// 让新代码风格一致。老页面不强行改(超出本次范围),逐步收敛。
//
// 命名:s = spacing(逻辑像素),r = radius(圆角)。数字就是像素值。

/// 间距常量(逻辑像素)。
class Spacing {
  const Spacing._();

  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;
}

/// 圆角常量(逻辑像素)。
class RadiusCorners {
  const RadiusCorners._();

  static const double r8 = 8;
  static const double r10 = 10;
  static const double r12 = 12;
  static const double r16 = 16;
}
