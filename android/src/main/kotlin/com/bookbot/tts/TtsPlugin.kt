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

  @Suppress("UNCHECKED_CAST")
  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    val wrapper = TtsMethodResultWrapper(result)
    when(call.method){
      "initModels" -> {
        pluginBinding?.applicationContext?.let { context ->
          val args = call.arguments as Map<*, *>
          val fastSpeechModel = args["fastSpeechModel"] as String
          val melganModel = args["melganModel"] as String
          val modelVersion = args["modelVersion"] as Int
          val threadCount = args["threadCount"] as Int
          TtsManager.instance.logEnabled = (args["logEnabled"] as? Boolean) ?: true
          TtsManager.instance.init(context, modelVersion, threadCount, fastSpeechModel, melganModel) {
            wrapper.success(null)
          }
        }
      }
      "speakText" -> {
        pluginBinding?.applicationContext?.let { context ->
          val args = call.arguments as Map<*, *>
          TtsManager.instance.logEnabled = (args["logEnabled"] as? Boolean) ?: true
          val request = RequestInfo(args, wrapper)
          TtsManager.instance.init(context, request.modelVersion, request.threadCount, request.fastSpeechModel, request.melganModel) {
            TtsManager.instance.speak(request)
          }
        }
      }
      "dispose" -> {
        TtsManager.instance.dispose()
      }
      else -> wrapper.notImplemented()
    }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    pluginBinding = null
  }
}
