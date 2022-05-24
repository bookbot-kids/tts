package com.bookbot.tts

import androidx.annotation.NonNull
import com.tensorspeech.tensorflowtts.tts.TtsManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result


/** TtsPlugin */
class TtsPlugin: FlutterPlugin, MethodCallHandler {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private lateinit var channel : MethodChannel
  private var pluginBinding: FlutterPlugin.FlutterPluginBinding? = null


  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "tts")
    channel.setMethodCallHandler(this)
    pluginBinding = flutterPluginBinding
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    when(call.method){
      "initModels" -> {
        pluginBinding?.applicationContext?.let { context ->
          val args = call.arguments as Map<*, *>
          val fastSpeechModel = args["fastSpeechModel"] as String
          val melganModel = args["melganModel"] as String
          TtsManager.instance.init(context, fastSpeechModel, melganModel) {
            result.success(null)
          }
        }
      }
      "speakText" -> {
        pluginBinding?.applicationContext?.let { context ->
          val args = call.arguments as Map<*, *>
          val fastSpeechModel = args["fastSpeechModel"] as String
          val melganModel = args["melganModel"] as String
          val text = args["text"] as String
          val speed = args["speed"] as Double
          TtsManager.instance.init(context, fastSpeechModel, melganModel) {
            TtsManager.instance.speak(text, speed.toFloat(), true)
            result.success(null)
          }
        }
      }
      else -> result.notImplemented()
    }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    pluginBinding = null
  }
}
