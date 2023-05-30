#include "tts_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <sstream>

namespace tts {

// static
void TtsPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "tts",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<TtsPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

TtsPlugin::TtsPlugin() {
    ttsManager = new TtsManager();
}

TtsPlugin::~TtsPlugin() {
    ttsManager = nullptr;
}

void TtsPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name().compare("initModels") == 0) {   
      const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
      auto fastSpeechModel_it = (args->find(flutter::EncodableValue("fastSpeechModel")))->second;
      auto melganModel_it = (args->find(flutter::EncodableValue("melganModel")))->second;
      std::string fastSpeechModel = std::get<std::string>(fastSpeechModel_it);
      std::string melganModel = std::get<std::string>(melganModel_it);
      ttsManager->initModel(fastSpeechModel, melganModel);
      result->Success(flutter::EncodableValue(TRUE));
  } else if (method_call.method_name().compare("speakText") == 0) {  
      const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
      ttsManager->speakText(args, std::move(result));
  } if (method_call.method_name().compare("playVoice") == 0) {   
      const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
      ttsManager->playVoice(args, std::move(result));
  }  if (method_call.method_name().compare("generateVoice") == 0) {  
      const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
      ttsManager->generateVoice(args, std::move(result));
  } if (method_call.method_name().compare("dispose") == 0) {   
      ttsManager->dispose(std::move(result));
  } else {
    result->NotImplemented();
  }
}

}  // namespace tts
