import 'dart:typed_data';

/// 听歌识曲接口要的录音格式：8 kHz、16 位小端、单声道。
const recognitionSampleRate = 8000;

/// 把录到的 16 位小端 PCM 转成识曲格式。麦克风不支持 8 kHz 单声道时（Windows 会按设备调整）
/// 先合并声道，再按区间取平均降采样。
Uint8List toRecognitionPcm(
  Uint8List bytes, {
  required int sampleRate,
  required int channels,
}) {
  if (sampleRate == recognitionSampleRate && channels == 1) return bytes;
  final input = ByteData.sublistView(bytes);
  final frames = bytes.lengthInBytes ~/ (2 * channels);
  final length = frames * recognitionSampleRate ~/ sampleRate;
  final output = ByteData(length * 2);
  for (var i = 0; i < length; i++) {
    final start = i * sampleRate ~/ recognitionSampleRate;
    final end = ((i + 1) * sampleRate ~/ recognitionSampleRate).clamp(
      start + 1,
      frames,
    );
    var sum = 0;
    for (var f = start; f < end; f++) {
      for (var c = 0; c < channels; c++) {
        sum += input.getInt16((f * channels + c) * 2, Endian.little);
      }
    }
    output.setInt16(i * 2, sum ~/ ((end - start) * channels), Endian.little);
  }
  return output.buffer.asUint8List();
}
