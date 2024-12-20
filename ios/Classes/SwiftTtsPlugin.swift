import Flutter
import UIKit

public class SwiftTtsPlugin: NSObject, FlutterPlugin {
    private let tts = TTS()
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "tts", binaryMessenger: registrar.messenger())
    let instance = SwiftTtsPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

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
