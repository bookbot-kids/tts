class Parameters {
  static const enSampleRate = 44100;
  static const enHopSize = 512;
  static const enEos = 77;
  static const idEos = 38;
  static const enDot = 72;
  static const idDot = 33;

  static const eosInputIds = <String, int>{
    'en': enEos,
    'id': idEos,
  };

  static const specialInputIds = <String, Map<String, int>>{
    'en': {
      '!': 70,
      ',': 71,
      '.': enDot,
      ':': 75,
      ';': 74,
      '?': 73,
    },
    'id': {
      '!': 31,
      ',': 32,
      '.': idDot,
      ':': 36,
      ';': 35,
      '?': 34,
    },
  };
}

class RequestInfo {
  final String fastSpeechModel;
  final String melganModel;
  final List<int> inputIds;
  final List<String> visemes;
  double speed;
  int speakerId;
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

  /// delay time in milliseconds before notify complete
  int playerCompletedDelayed;

  RequestInfo(
    this.fastSpeechModel,
    this.melganModel,
    this.inputIds,
    this.visemes, {
    this.speed = 1.0,
    this.speakerId = 0,
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
  });
}
