import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanade/data/recognition_pcm.dart';

Uint8List _pcm(List<int> samples) {
  final data = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(i * 2, samples[i], Endian.little);
  }
  return data.buffer.asUint8List();
}

List<int> _samples(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  return [
    for (var i = 0; i < bytes.lengthInBytes ~/ 2; i++)
      data.getInt16(i * 2, Endian.little),
  ];
}

void main() {
  test('8 kHz mono is passed through unchanged', () {
    final pcm = _pcm([1, -2, 3]);
    expect(
      identical(toRecognitionPcm(pcm, sampleRate: 8000, channels: 1), pcm),
      isTrue,
    );
  });

  test('stereo 16 kHz averages channels and pairs of frames', () {
    // 4 帧双声道 → 2 个 8 kHz 单声道采样
    final pcm = _pcm([100, 300, 200, 400, -1000, -3000, -2000, -4000]);
    expect(_samples(toRecognitionPcm(pcm, sampleRate: 16000, channels: 2)), [
      250,
      -2500,
    ]);
  });

  test('48 kHz keeps one second as 8000 samples', () {
    final pcm = _pcm(List.filled(48000, 1234));
    final out = _samples(toRecognitionPcm(pcm, sampleRate: 48000, channels: 1));
    expect(out.length, 8000);
    expect(out.every((v) => v == 1234), isTrue);
  });

  test('44.1 kHz stereo keeps the duration', () {
    final pcm = _pcm(List.filled(44100 * 2, -7));
    final out = _samples(toRecognitionPcm(pcm, sampleRate: 44100, channels: 2));
    expect(out.length, 8000);
    expect(out.every((v) => v == -7), isTrue);
  });
}
