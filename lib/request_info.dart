class Parameters {
  static const enSampleRate = 44100;
  static const enHopSize = 512;
  static const enEos = 2;
  static const enDot = 12;
  static const idEos = 2;
  static const idDot = 12;
  static const swEos = 2;
  static const swDot = 12;

  static const eosInputIds = <String, int>{
    'en': enEos,
    'sw': swEos,
    'id': idEos,
  };

  static const specialInputIds = <String, Map<String, int>>{
    'en': {
      '!': 4,
      ',': 10,
      '.': enDot,
      ':': 13,
      ';': 14,
      '?': 15,
    },
    'id': {
      '!': 4,
      ',': 10,
      '.': idDot,
      ':': 13,
      ';': 14,
      '?': 15,
    },
    'sw': {
      '!': 4,
      ',': 10,
      '.': swDot,
      ':': 13,
      ';': 14,
      '?': 15,
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

  /// delay time in milliseconds before notify complete
  int playerCompletedDelayed;

  RequestInfo(
    this.models,
    this.inputIds,
    this.visemes, {
    this.speed = 1.0,
    this.speaker = Speaker.us,
    this.useDot = true,
    this.sampleRate = Parameters.enSampleRate,
    this.hopSize = Parameters.enHopSize,
    this.eos = Parameters.enEos,
    this.dot = Parameters.enDot,
    this.requestId = '',
    this.singleThread = true,
    this.playerCompletedDelayed = 0,
    this.useEos = true,
    this.modelVersion = 1,
    this.logEnabled = true,
    this.threadCount = 1,
  });
}
