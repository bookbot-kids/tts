class Parameters {
  static const defaultSampleRate = 44100;
  static const defaultHopSize = 512;
  static const enEos = 2;
  static const idEos = 2;
  static const swEos = 2;

  static const eosInputIds = <String, int>{
    'en': enEos,
    'sw': swEos,
    'id': idEos,
  };

  static const specialInputIds = <String, Map<String, int>>{
    'en': {
      '!': 4,
      ',': 10,
      '.': 12,
      ':': 13,
      ';': 14,
      '?': 15,
      ' ': 3,
    },
    'id': {
      '!': 4,
      ',': 10,
      '.': 12,
      ':': 13,
      ';': 14,
      '?': 15,
      ' ': 3,
    },
    'sw': {
      '!': 4,
      ',': 10,
      '.': 12,
      ':': 13,
      ';': 14,
      '?': 15,
      ' ': 3,
    },
  };
}

enum Speaker {
  us(2),
  au(0),
  gb(1),
  // no speaker id
  id(-1),
  // no speaker id
  sw(-1);

  final int speakerId;

  const Speaker(this.speakerId);
}

class RequestInfo {
  final List<String> models;
  final List<int> inputIds;
  final List<String> visemes;
  double speed;
  Speaker speaker;
  bool useDot;
  int sampleRate;
  int hopSize;
  int eos;
  int dot;
  String requestId;
  bool singleThread;
  bool useEos;
  int modelVersion;
  bool logEnabled;
  int threadCount;
  bool useEndSpace;
  final String language;
  int space;
  bool enableLids;

  /// delay time in milliseconds before notify complete
  int playerCompletedDelayed;

  RequestInfo(
    this.models,
    this.inputIds,
    this.visemes,
    this.language, {
    this.speed = 1.0,
    this.speaker = Speaker.us,
    this.useDot = false,
    this.sampleRate = Parameters.defaultSampleRate,
    this.hopSize = Parameters.defaultHopSize,
    this.eos = 0,
    this.dot = 0,
    this.requestId = '',
    this.singleThread = true,
    this.playerCompletedDelayed = 0,
    this.useEos = true,
    this.modelVersion = 1,
    this.logEnabled = true,
    this.threadCount = 1,
    this.useEndSpace = false,
    this.space = 0,
    this.enableLids = false,
  }) {
    eos = Parameters.eosInputIds[language]!;
    dot = Parameters.specialInputIds[language]!['.']!;
    space = Parameters.specialInputIds[language]![' ']!;
  }

  Map toMap() => {
        'models': models,
        'inputIds': inputIds,
        'speed': speed,
        'speakerId': speaker.speakerId,
        'sampleRate': sampleRate,
        'hopSize': hopSize,
        'requestId': requestId,
        'singleThread': singleThread,
        'playerCompletedDelayed': playerCompletedDelayed,
        'modelVersion': modelVersion,
        'logEnabled': logEnabled,
        'threadCount': threadCount,
        'enableLids': enableLids
      };
}
