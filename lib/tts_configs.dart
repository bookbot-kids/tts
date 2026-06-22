/// Default audio and token parameters for TTS models across languages.
class Parameters {
  /// Default audio sample rate in Hz.
  static const defaultSampleRate = 44100;

  /// Default hop size (frame shift) in samples, used to convert
  /// duration frames to seconds: `duration_sec = frames * hopSize / sampleRate`.
  static const defaultHopSize = 512;
}

/// Languages supported by the TTS models.
///
/// Each variant carries its [code] (the string used across the public API,
/// e.g. `'en'`) and resolves its model token IDs via [eos] and
/// [specialInputIds]. Both are implemented with exhaustive `switch`
/// statements over this enum, so adding a new language causes a compile-time
/// error until every token mapping is provided — there is no silent fallback.
enum Language {
  /// English.
  en('en'),

  /// Indonesian.
  id('id'),

  /// Swahili.
  sw('sw'),

  /// Spanish.
  es('es');

  /// Language code used in the public API (e.g. `'en'`).
  final String code;

  const Language(this.code);

  /// Resolves a [Language] from its [code], throwing if unsupported.
  static Language fromCode(String code) => Language.values.firstWhere(
        (language) => language.code == code,
        orElse: () => throw ArgumentError('Unsupported language code: $code'),
      );

  /// End-of-sequence token ID for this language.
  int get eos {
    switch (this) {
      case Language.en:
      case Language.id:
      case Language.sw:
      case Language.es:
        return 2;
    }
  }

  /// Maps punctuation/special characters to their model input IDs.
  Map<String, int> get specialInputIds {
    switch (this) {
      case Language.en:
      case Language.id:
      case Language.sw:
      case Language.es:
        return const {
          '!': 4,
          ',': 10,
          '.': 12,
          ':': 13,
          ';': 14,
          '?': 15,
          ' ': 3,
        };
    }
  }

  /// Dot (period) token ID for this language.
  int get dot => specialInputIds['.']!;

  /// Space token ID for this language.
  int get space => specialInputIds[' ']!;
}

/// ONNX Runtime execution provider used for inference.
///
/// Currently only honoured on Android; iOS always uses its default provider.
enum OrtProvider {
  /// Default ONNX Runtime CPU execution provider (most compatible).
  cpu('cpu'),

  /// XNNPACK EP — typically fastest on ARM with multi-threading.
  xnnpack('xnnpack'),

  /// Android NNAPI EP — may fail on unsupported ops (e.g. GATHER rank mismatch).
  nnapi('nnapi');

  /// Native-side identifier sent over the method channel.
  final String nativeName;

  const OrtProvider(this.nativeName);
}

/// Speaker variants for multi-speaker TTS models.
///
/// The [speakerId] is passed to the ONNX model's `sids` input tensor.
/// A value of -1 indicates no speaker ID (single-speaker model).
enum Speaker {
  /// US English speaker.
  us(2),

  /// Australian English speaker.
  au(0),

  /// British English speaker.
  gb(1),

  /// Indonesian (single-speaker, no speaker ID).
  id(-1),

  /// Swahili (single-speaker, no speaker ID).
  sw(-1),

  /// Spanish (single-speaker, no speaker ID).
  es(-1);

  /// Numeric ID passed to the model. -1 means speaker ID is omitted.
  final int speakerId;

  const Speaker(this.speakerId);
}
