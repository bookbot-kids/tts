class Parameters {
  static const enSampleRate = 44100;
  static const enHopSize = 256;
  static const enEos = 77;
  static const idEos = 2;
  static const enDot = 72;
  static const idDot = 6;
  static const intersperse = 0;

  static const enSpace = 75; // change later
  static const idSpace = 9;

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
      ' ': enSpace,
    },
    'id': {
      '!': 7,
      ',': 5,
      '.': idDot,
      ':': 4,
      ';': 3,
      '?': 8,
      ' ': idSpace,
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
  int threadCount;
  int space;

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
    this.useEos = false,
    this.modelVersion = 1,
    this.logEnabled = true,
    this.threadCount = 1,
    this.space = Parameters.enSpace,
  });
}
