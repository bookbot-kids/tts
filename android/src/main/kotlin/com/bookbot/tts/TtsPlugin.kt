package com.bookbot.tts

import com.tensorspeech.tensorflowtts.tts.TtsManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result


/**
 * Flutter plugin entry point for Android TTS functionality.
 *
 * Registers a [MethodChannel] named `"tts"` and delegates incoming method
 * calls (`initModels`, `speakText`, `generateVoice`, `playVoice`, `dispose`)
 * to [TtsManager].
 */
class TtsPlugin: FlutterPlugin, MethodCallHandler {
  /** Method channel for Flutter ↔ native Android communication. */
  private lateinit var channel : MethodChannel
  /** Plugin binding used to obtain the application context. */
  private var pluginBinding: FlutterPlugin.FlutterPluginBinding? = null


  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "tts")
    channel.setMethodCallHandler(this)
    pluginBinding = flutterPluginBinding
  }

  @Suppress("UNCHECKED_CAST")
  override fun onMethodCall(call: MethodCall, result: Result) {
    val wrapper = TtsMethodResultWrapper(result)
    when(call.method){
      "initModels" -> {
        pluginBinding?.applicationContext?.let { context ->
          val args = call.arguments as Map<*, *>
          val models = args["models"] as List<String>
          val modelVersion = args["modelVersion"] as Int
          val threadCount = args["threadCount"] as Int
          TtsManager.instance.logEnabled = (args["logEnabled"] as? Boolean) != false
          TtsManager.instance.init(context, modelVersion, threadCount, models) {
            wrapper.success(null)
          }
        }
      }
      "speakText" -> {
        pluginBinding?.applicationContext?.let { context ->
          val args = call.arguments as Map<*, *>
          TtsManager.instance.logEnabled = (args["logEnabled"] as? Boolean) != false
          val request = RequestInfo(args, wrapper)
          TtsManager.instance.init(context, request.modelVersion, request.threadCount, request.models) {
            TtsManager.instance.speak(request)
          }
        }
      }
      "playVoice" -> {
        pluginBinding?.applicationContext?.let { context ->
          val args = call.arguments as Map<*, *>
          TtsManager.instance.logEnabled = (args["logEnabled"] as? Boolean) != false
          val request = RequestInfo(args, wrapper)
          TtsManager.instance.init(context, request.modelVersion, request.threadCount, request.models) {
            TtsManager.instance.playVoice(request)
          }
        }
      }
      "generateVoice"-> {
        pluginBinding?.applicationContext?.let { context ->
          val args = call.arguments as Map<*, *>
          TtsManager.instance.logEnabled = (args["logEnabled"] as? Boolean) != false
          val request = RequestInfo(args, wrapper)
          TtsManager.instance.init(context, request.modelVersion, request.threadCount, request.models) {
            TtsManager.instance.generateVoice(request)
          }
        }
      }
      "dispose" -> {
        TtsManager.instance.dispose()
      }
      else -> wrapper.notImplemented()
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    pluginBinding = null
  }
}
