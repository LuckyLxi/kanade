import '../src/rust/api/types.dart';

/// 播放错误。文案在界面层按当前语言生成。
sealed class PlayerError {
  const PlayerError();
}

class PlaybackFailed extends PlayerError {
  const PlaybackFailed(this.song, this.cause);

  final Song song;
  final Object cause;
}

/// media_kit 播放过程中报告的错误原文。
class StreamFailed extends PlayerError {
  const StreamFailed(this.message);

  final String message;
}
