#include "include/tts/tts_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "tts_plugin.h"

void TtsPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  tts::TtsPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
