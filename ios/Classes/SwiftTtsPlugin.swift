import Flutter
import UIKit

/// Flutter plugin entry point for iOS TTS functionality.
///
/// Registers a `FlutterMethodChannel` named `"tts"` and delegates incoming
/// method calls (`initModels`, `speakText`, `generateVoice`, `playVoice`,
/// `dispose`) to the underlying ``TTS`` engine.
public class SwiftTtsPlugin: NSObject, FlutterPlugin {
    /// Shared TTS engine instance used for all method-channel calls.
    private let tts = TTS()

  /// Registers the plugin with the Flutter engine and sets up the method channel.
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "tts", binaryMessenger: registrar.messenger())
    let instance = SwiftTtsPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  /// Handles incoming method calls from the Dart side.
  ///
  /// Supported methods:
  /// - `initModels` – pre-loads ONNX model files.
  /// - `speakText` – runs inference and plays audio immediately.
  /// - `generateVoice` – runs inference only, caches audio for later playback.
  /// - `playVoice` – plays a previously cached audio buffer.
  /// - `dispose` – releases all cached audio buffers.
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
      switch call.method {
          case "initModels":
            let argurments = call.arguments as! Dictionary<String, Any>
            let models = argurments["models"] as! Array<String>
            tts.logEnabled = argurments["logEnabled"] as? Bool ?? true
            tts.threadCount = argurments["threadCount"] as? Int ?? 1
            tts.initModel(models: models) { completedResult in
              result(completedResult)
            }
            break
          case "speakText":
            let argurments = call.arguments as! Dictionary<String, Any>
            let requestInfo = RequestInfo(args: argurments)
            tts.logEnabled =  requestInfo.logEnabled
            tts.threadCount = requestInfo.threadCount
            tts.speak(requestInfo: requestInfo, result: result)
            break
          case "generateVoice":
            let argurments = call.arguments as! Dictionary<String, Any>
            let requestInfo = RequestInfo(args: argurments)
            tts.logEnabled =  requestInfo.logEnabled
            tts.threadCount = requestInfo.threadCount
            tts.generateVoice(requestInfo: requestInfo, result: result)
            break
          case "playVoice":
            let argurments = call.arguments as! Dictionary<String, Any>
            let requestInfo = RequestInfo(args: argurments)
            tts.logEnabled =  requestInfo.logEnabled
            tts.threadCount = requestInfo.threadCount
            tts.playVoice(requestInfo: requestInfo, result: result)
            break
            case "dispose":
            tts.dispose()
            break
          default :
              result(FlutterMethodNotImplemented)
      }
  }
}
