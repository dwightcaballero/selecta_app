import 'dart:io';
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Singleton service responsible for high-performance, loud, and crisp
/// audio and haptic feedback during warehouse picking and barcode scanning.
///
/// Pre-synthesizes PCM WAV audio files written to local cache storage to guarantee
/// instant, rock-solid loudspeaker playback on Android & iOS without relying on system touch clicks.
class SoundFeedbackService {
  static final SoundFeedbackService _instance = SoundFeedbackService._internal();
  factory SoundFeedbackService() => _instance;
  SoundFeedbackService._internal();

  final AudioPlayer _player = AudioPlayer();
  String? _chimeFilePath;
  String? _buzzerFilePath;
  bool _isInitialized = false;

  /// Initializes audio engine, sets audio context for loudspeaker alerts,
  /// and persists synthesized WAV sound files.
  Future<void> init() async {
    if (_isInitialized) return;
    try {
      await _player.setReleaseMode(ReleaseMode.stop);

      try {
        await _player.setAudioContext(
          AudioContext(
            android: const AudioContextAndroid(
              // Media stream keeps playing in vibrate/silent ringer mode
              // (sonification/touch-sound usage is muted there).
              isSpeakerphoneOn: false,
              stayAwake: false,
              contentType: AndroidContentType.music,
              usageType: AndroidUsageType.media,
              audioFocus: AndroidAudioFocus.gainTransientMayDuck,
            ),
            iOS: AudioContextIOS(
              category: AVAudioSessionCategory.playback,
              options: const {
                AVAudioSessionOptions.mixWithOthers,
                AVAudioSessionOptions.defaultToSpeaker,
              },
            ),
          ),
        );
      } catch (ctxErr) {
        debugPrint('[SoundFeedbackService] AudioContext warning: $ctxErr');
      }

      final tempDir = await getTemporaryDirectory();
      final chimeFile = File('${tempDir.path}/scan_success_chime.wav');
      final buzzerFile = File('${tempDir.path}/scan_error_buzzer.wav');

      final chimeBytes = _synthesizeChimeWav();
      final buzzerBytes = _synthesizeBuzzerWav();

      await chimeFile.writeAsBytes(chimeBytes, flush: true);
      await buzzerFile.writeAsBytes(buzzerBytes, flush: true);

      _chimeFilePath = chimeFile.path;
      _buzzerFilePath = buzzerFile.path;
      _isInitialized = true;
      debugPrint('[SoundFeedbackService] Initialized with files: $_chimeFilePath, $_buzzerFilePath');
    } catch (e, st) {
      debugPrint('[SoundFeedbackService] Init error: $e\n$st');
    }
  }

  /// Plays a soft, melodic two-tone success chime with light haptic feedback.
  Future<void> playSuccessChime() async {
    HapticFeedback.lightImpact();
    try {
      if (_chimeFilePath == null) await init();
      if (_chimeFilePath != null && File(_chimeFilePath!).existsSync()) {
        await _player.stop();
        await _player.play(DeviceFileSource(_chimeFilePath!), volume: 1.0);
      } else {
        final bytes = _synthesizeChimeWav();
        await _player.stop();
        await _player.play(BytesSource(bytes), volume: 1.0);
      }
    } catch (e, st) {
      debugPrint('[SoundFeedbackService] playSuccessChime error: $e\n$st');
      SystemSound.play(SystemSoundType.click);
    }
  }

  /// Plays a loud, unmistakable double-burst error buzzer with strong, repeated vibration.
  Future<void> playErrorBuzzer() async {
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 140), () => HapticFeedback.heavyImpact());
    Future.delayed(const Duration(milliseconds: 280), () => HapticFeedback.heavyImpact());

    try {
      if (_buzzerFilePath == null) await init();
      if (_buzzerFilePath != null && File(_buzzerFilePath!).existsSync()) {
        await _player.stop();
        await _player.play(DeviceFileSource(_buzzerFilePath!), volume: 1.0);
      } else {
        final bytes = _synthesizeBuzzerWav();
        await _player.stop();
        await _player.play(BytesSource(bytes), volume: 1.0);
      }
    } catch (e, st) {
      debugPrint('[SoundFeedbackService] playErrorBuzzer error: $e\n$st');
      SystemSound.play(SystemSoundType.alert);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PURE DART SYNTHESIS: RIFF PCM 16-BIT MONO WAV GENERATOR
  // ═══════════════════════════════════════════════════════════════════════════

  /// Generates a pleasant two-tone chime (C6 at 1046.5 Hz followed by E6 at 1318.5 Hz)
  /// with a smooth decaying envelope.
  static Uint8List _synthesizeChimeWav() {
    const int sampleRate = 22050;
    const double tone1Duration = 0.09; // 90ms
    const double tone2Duration = 0.16; // 160ms
    final int totalSamples = ((tone1Duration + tone2Duration) * sampleRate).toInt();

    final Float32List floatSamples = Float32List(totalSamples);
    final int tone1Samples = (tone1Duration * sampleRate).toInt();

    // Tone 1: 1046.5 Hz (C6) with gentle attack & decay
    for (int i = 0; i < tone1Samples; i++) {
      final double t = i / sampleRate;
      final double env = math.sin((i / tone1Samples) * math.pi);
      floatSamples[i] = (math.sin(2 * math.pi * 1046.5 * t) * 0.7 * env).toDouble();
    }

    // Tone 2: 1318.5 Hz (E6) with exponential bell decay
    for (int i = tone1Samples; i < totalSamples; i++) {
      final int relIdx = i - tone1Samples;
      final int relTotal = totalSamples - tone1Samples;
      final double t = relIdx / sampleRate;
      final double decay = math.exp(-4.5 * (relIdx / relTotal));
      final double harmonic = math.sin(2 * math.pi * 1318.5 * t) * 0.75 +
          math.sin(2 * math.pi * 2637.0 * t) * 0.15;
      floatSamples[i] = (harmonic * decay).toDouble();
    }

    return _encodeWav(floatSamples, sampleRate);
  }

  /// Generates a loud, harsh warehouse error buzzer (two 160ms 180Hz square-saw buzzes)
  /// with strong harmonic overtones to cut through ambient machinery/compressor noise.
  static Uint8List _synthesizeBuzzerWav() {
    const int sampleRate = 22050;
    const double totalDuration = 0.44; // 440ms
    final int totalSamples = (totalDuration * sampleRate).toInt();
    final Float32List floatSamples = Float32List(totalSamples);

    final int burst1End = (0.17 * sampleRate).toInt(); // 0 - 170ms: Buzz 1
    final int gapEnd = (0.23 * sampleRate).toInt();    // 170 - 230ms: Gap
    final int burst2End = (0.40 * sampleRate).toInt(); // 230 - 400ms: Buzz 2

    for (int i = 0; i < totalSamples; i++) {
      if (i < burst1End || (i >= gapEnd && i < burst2End)) {
        final double t = i / sampleRate;
        // 185 Hz fundamental + 370 Hz + 555 Hz odd/even harmonics for harsh buzzer buzz
        final double wave = (math.sin(2 * math.pi * 185.0 * t) * 0.5) +
            (math.sin(2 * math.pi * 370.0 * t) * 0.3) +
            (math.sin(2 * math.pi * 555.0 * t) * 0.2);
        // Soft clipping for harsh saturation
        floatSamples[i] = (wave * 1.2).clamp(-0.95, 0.95);
      } else {
        floatSamples[i] = 0.0;
      }
    }

    return _encodeWav(floatSamples, sampleRate);
  }

  /// Packages 16-bit PCM Mono audio samples into standard RIFF WAVE bytes.
  static Uint8List _encodeWav(Float32List samples, int sampleRate) {
    final int numSamples = samples.length;
    final int dataSize = numSamples * 2; // 16-bit = 2 bytes per sample
    final int fileSize = 44 + dataSize;
    final Uint8List buffer = Uint8List(fileSize);
    final ByteData byteData = ByteData.view(buffer.buffer);

    // 0-3: "RIFF"
    buffer.setRange(0, 4, 'RIFF'.codeUnits);
    // 4-7: ChunkSize = FileSize - 8
    byteData.setUint32(4, fileSize - 8, Endian.little);
    // 8-11: "WAVE"
    buffer.setRange(8, 12, 'WAVE'.codeUnits);
    // 12-15: "fmt "
    buffer.setRange(12, 16, 'fmt '.codeUnits);
    // 16-19: Subchunk1Size = 16 for PCM
    byteData.setUint32(16, 16, Endian.little);
    // 20-21: AudioFormat = 1 (PCM)
    byteData.setUint16(20, 1, Endian.little);
    // 22-23: NumChannels = 1 (Mono)
    byteData.setUint16(22, 1, Endian.little);
    // 24-27: SampleRate
    byteData.setUint32(24, sampleRate, Endian.little);
    // 28-31: ByteRate = SampleRate * NumChannels * BitsPerSample / 8
    byteData.setUint32(28, sampleRate * 2, Endian.little);
    // 32-33: BlockAlign = NumChannels * BitsPerSample / 8
    byteData.setUint16(32, 2, Endian.little);
    // 34-35: BitsPerSample = 16
    byteData.setUint16(34, 16, Endian.little);
    // 36-39: "data"
    buffer.setRange(36, 40, 'data'.codeUnits);
    // 40-43: Subchunk2Size = NumSamples * 2
    byteData.setUint32(40, dataSize, Endian.little);

    // 44+: PCM 16-bit signed integer samples
    int offset = 44;
    for (int i = 0; i < numSamples; i++) {
      final double sample = samples[i].clamp(-1.0, 1.0);
      final int intSample = (sample * 32767.0).toInt().clamp(-32768, 32767);
      byteData.setInt16(offset, intSample, Endian.little);
      offset += 2;
    }

    return buffer;
  }
}
