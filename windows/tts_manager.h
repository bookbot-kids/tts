#ifndef FLUTTER_PLUGIN_TTS_MANAGER_H_
#define FLUTTER_PLUGIN_TTS_MANAGER_H_

// This must be included before many other Windows headers.
#include <windows.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
// CppFlow headers
#include "cppflow/cppflow.h"
#include <memory>
#include <sstream>

namespace tts {
 class TtsManager {
    public:
        TtsManager();
        virtual ~TtsManager();
        void initModel(std::string fastSpeechModel, std::string melganModel);
        void speakText(const flutter::EncodableMap* args, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
        void playVoice(const flutter::EncodableMap* args, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
        void generateVoice(const flutter::EncodableMap* args, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
        void dispose(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
 private:
     bool initialized;
     std::unique_ptr<cppflow::model> lightspeech;
     std::unique_ptr<cppflow::model> mbmelgan;
 };
}
#endif  // FLUTTER_PLUGIN_TTS_MANAGER_H_