import Flutter
import UIKit

@available(iOS 13.0, *)
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
            let fastSpeechModel = argurments["fastSpeechModel"]
            let melganModel = argurments["melganModel"]
            break
          case "speakText":
              let argurments = call.arguments as! Dictionary<String, Any>
              let fastSpeechModel = argurments["fastSpeechModel"]
              let melganModel = argurments["melganModel"]
              let text = argurments["text"] as! String
              let speed = argurments["speed"] as! NSNumber
              tts.speak(string: text)
              result(nil)
            break
          default :
              result(FlutterMethodNotImplemented)
      }
  }
}
