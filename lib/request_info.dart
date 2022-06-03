class RequestInfo {
  // english params
  static const enSampleRate = 44100;
  static const enHopSize = 512;
  static const enEos = 95; // end of sentence

  // indonesian params
  static const idSampleRate = 22050;
  static const idHopSize = 256;
  static const idEos = 148;

  static const defaultDot = 7; // dot (.)
  static const eosText = 'eos';

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

  RequestInfo(
    this.fastSpeechModel,
    this.melganModel,
    this.inputIds,
    this.visemes, {
    this.speed = 1.0,
    this.speakerId = 0,
    this.useDot = true,
    this.sampleRate = enSampleRate,
    this.hopSize = enHopSize,
    this.eos = enEos,
    this.dot = defaultDot,
  });
}
