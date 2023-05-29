#ifndef FLUTTER_PLUGIN_TTS_PLUGIN_H_
#define FLUTTER_PLUGIN_TTS_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace tts {

class TtsPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  TtsPlugin();

  virtual ~TtsPlugin();

  // Disallow copy and assign.
  TtsPlugin(const TtsPlugin&) = delete;
  TtsPlugin& operator=(const TtsPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace tts

#endif  // FLUTTER_PLUGIN_TTS_PLUGIN_H_
