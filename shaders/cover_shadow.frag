#version 460 core

#include <flutter/runtime_effect.glsl>

// 封面圆角矩形的高斯投影（Evan Wallace 的解析近似：x 方向用 erf 积分，y 方向数值积分 4 次）。
// 全程浮点计算再抖动，代替安卓上 BoxShadow 那种一级一级的台阶。

// 投影矩形（已加上偏移和扩展），本地坐标
uniform vec4 uRect;
uniform float uRadius;
uniform float uSigma;
// 不预乘的颜色
uniform vec4 uColor;

out vec4 fragColor;

float gaussian(float x, float sigma) {
  return exp(-(x * x) / (2.0 * sigma * sigma)) / (2.50662827 * sigma);
}

vec2 erf2(vec2 x) {
  vec2 s = sign(x);
  vec2 a = abs(x);
  x = 1.0 + (0.278393 + (0.230389 + 0.078108 * (a * a)) * a) * a;
  x *= x;
  return s - s / (x * x);
}

float shadowX(float x, float y, float sigma, float corner, vec2 halfSize) {
  float delta = min(halfSize.y - corner - abs(y), 0.0);
  float curved = halfSize.x - corner + sqrt(max(0.0, corner * corner - delta * delta));
  vec2 integral = 0.5 + 0.5 * erf2((x + vec2(-curved, curved)) * (sqrt(0.5) / sigma));
  return integral.y - integral.x;
}

float hash(vec2 p) {
  vec3 p3 = fract(p.xyx * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 halfSize = (uRect.zw - uRect.xy) * 0.5;
  vec2 point = frag - (uRect.xy + uRect.zw) * 0.5;
  float corner = min(uRadius, min(halfSize.x, halfSize.y));
  float sigma = max(uSigma, 0.01);

  float low = point.y - halfSize.y;
  float high = point.y + halfSize.y;
  float start = clamp(-3.0 * sigma, low, high);
  float end = clamp(3.0 * sigma, low, high);
  float step = (end - start) / 4.0;
  float y = start + step * 0.5;
  float a = 0.0;
  for (int i = 0; i < 4; i++) {
    a += shadowX(point.x, point.y - y, sigma, corner, halfSize) * gaussian(y, sigma) * step;
    y += step;
  }
  a *= uColor.a;
  a = clamp(a + (hash(frag) - hash(frag + 71.3)) / 255.0, 0.0, 1.0);
  fragColor = vec4(uColor.rgb * a, a);
}
