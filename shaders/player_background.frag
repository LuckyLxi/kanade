#version 460 core

#include <flutter/runtime_effect.glsl>

// 播放页流动背景：把预模糊的小封面图旋转、缩放成三层叠在一起，再轻微扭曲让颜色像液体一样流动。
// 小图放大十几倍，硬件双线性插值会出现块状和斜纹，这里用 4 次双线性采样拼出双三次 B 样条插值，
// 放多大都是平滑的。最后提饱和、压住过亮的颜色、加一点抖动噪声消除暗部色带。

uniform vec2 uSize;
uniform float uTexSize;
// 流动相位，弧度，0–2π 一圈；所有频率都是它的整数倍，转一圈首尾无缝衔接
uniform float uPhase;
// 切歌淡入进度，0 是旧封面，1 是新封面
uniform float uMix;
// 封面 4 个主色（Dart 端已按 uMix 插值好），画成漂移的光斑，补上模糊后被平均掉的鲜艳颜色
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
uniform sampler2D uFrom;
uniform sampler2D uTo;

out vec4 fragColor;

const vec3 kLuma = vec3(0.2126, 0.7152, 0.0722);

vec3 samp(vec2 uv) {
  vec3 c = texture(uTo, uv).rgb;
  if (uMix < 1.0) c = mix(texture(uFrom, uv).rgb, c, uMix);
  return c;
}

vec4 cubic(float v) {
  vec4 n = vec4(1.0, 2.0, 3.0, 4.0) - v;
  vec4 s = n * n * n;
  float x = s.x;
  float y = s.y - 4.0 * s.x;
  float z = s.z - 4.0 * s.y + 6.0 * s.x;
  float w = 6.0 - x - y - z;
  return vec4(x, y, z, w) * (1.0 / 6.0);
}

vec3 bicubic(vec2 uv) {
  uv = uv * uTexSize - 0.5;
  vec2 f = fract(uv);
  uv -= f;
  vec4 xc = cubic(f.x);
  vec4 yc = cubic(f.y);
  vec4 c = uv.xxyy + vec2(-0.5, 1.5).xyxy;
  vec4 s = vec4(xc.xz + xc.yw, yc.xz + yc.yw);
  vec4 o = (c + vec4(xc.yw, yc.yw) / s) / uTexSize;
  float sx = s.x / (s.x + s.y);
  float sy = s.z / (s.z + s.w);
  return mix(mix(samp(o.yw), samp(o.xw), sx), mix(samp(o.yz), samp(o.xz), sx), sy);
}

// 超出 0–1 的部分镜像，旋转时不会露边
vec2 mirror(vec2 uv) {
  return 1.0 - abs(1.0 - mod(uv, 2.0));
}

vec3 layer(vec2 p, float angle, float scale, vec2 offset) {
  float c = cos(angle);
  float s = sin(angle);
  vec2 q = mat2(c, s, -s, c) * (p - offset) / scale + 0.5;
  return bicubic(mirror(q));
}

vec3 blob(vec3 col, vec2 p, vec3 color, vec2 center) {
  vec2 d = p - center;
  return mix(col, color, 0.6 * exp(-dot(d, d) / 0.07));
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float a = uPhase;
  // 以长边为 1 的坐标，原点在中心，横竖屏比例都不变形
  vec2 p = (frag - uSize * 0.5) / max(uSize.x, uSize.y);
  p += 0.035 * vec2(sin(p.y * 5.0 + a * 2.0), cos(p.x * 5.0 - a * 3.0));

  vec3 col = layer(p, a, 1.25, 0.12 * vec2(cos(a), sin(a)));
  col = mix(col, layer(p, 1.0 - 2.0 * a, 0.85, 0.16 * vec2(sin(2.0 * a), cos(a))), 0.3);
  col = mix(col, layer(p, 2.5 + 3.0 * a, 0.6, 0.2 * vec2(cos(3.0 * a), sin(2.0 * a))), 0.15);

  // 主色光斑沿不同频率的李萨如曲线漂移；按屏幕宽高各自归一化，竖屏手机上也都落在屏幕里
  vec2 b = frag / uSize - 0.5;
  col = blob(col, b, uC0, vec2(-0.25 + 0.2 * sin(3.0 * a), -0.3 + 0.15 * cos(2.0 * a)));
  col = blob(col, b, uC1, vec2(0.3 + 0.15 * cos(2.0 * a), -0.15 + 0.2 * sin(3.0 * a)));
  col = blob(col, b, uC2, vec2(-0.2 + 0.2 * cos(4.0 * a), 0.35 + 0.1 * sin(2.0 * a)));
  col = blob(col, b, uC3, vec2(0.2 + 0.2 * sin(2.0 * a), 0.2 + 0.2 * cos(5.0 * a)));

  // 模糊混色后颜色会发灰，提一下饱和度
  float l = dot(col, kLuma);
  col = clamp(mix(vec3(l), col, 1.7), 0.0, 1.0);
  // 浅色封面压暗到白字看得清的亮度，保持色相
  l = dot(col, kLuma);
  col *= min(1.0, 0.42 / max(l, 0.001));

  // 底部压暗给进度条和按钮，顶部略压
  float y = frag.y / uSize.y;
  col *= mix(0.9, 0.62, smoothstep(0.45, 1.0, y)) * mix(0.85, 1.0, smoothstep(0.0, 0.2, y));

  // 抖动噪声：8 位颜色在大面积暗色渐变里会出现一圈圈色带
  float n = fract(52.9829189 * fract(dot(frag, vec2(0.06711056, 0.00583715))));
  col += (n - 0.5) / 255.0;

  fragColor = vec4(col, 1.0);
}
