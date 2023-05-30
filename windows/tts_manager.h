#ifndef FLUTTER_PLUGIN_TTS_MANAGER_H_
#define FLUTTER_PLUGIN_TTS_MANAGER_H_

// This must be included before many other Windows headers.
#include <windows.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <sstream>

namespace tts {
 class TtsManager {
    public:
        TtsManager();
        virtual ~TtsManager();
        void initModel(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
        void speakText(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
        void playVoice(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
        void generateVoice(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
        void dispose(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
 };
}
#endif  // FLUTTER_PLUGIN_TTS_MANAGER_H_