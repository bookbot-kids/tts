#include "tts_manager.h"

// CppFlow headers
#include "cppflow/cppflow.h"

// C++ headers
#include <iostream>

// AudioFile headers
#include "AudioFile.hpp"

// copied from VoxCommons.hpp
typedef std::vector<std::tuple<std::string, cppflow::tensor>> TensorVec;

template <typename T>
struct TFTensor
{
    std::vector<T> Data;
    std::vector<int64_t> Shape;
    size_t TotalSize;
};

template <typename F>
TFTensor<F> CopyTensor(cppflow::tensor& InTens)
{
    std::vector<F> Data = InTens.get_data<F>();
    std::vector<int64_t> Shape = InTens.shape().get_data<int64_t>();
    size_t TotalSize = 1;
    for (const int64_t& Dim : Shape)
        TotalSize *= Dim;

    return TFTensor<F>{Data, Shape, TotalSize};
}

namespace tts { 
    TtsManager::TtsManager() {
    }

    TtsManager::~TtsManager() {
    }

    void TtsManager::initModel(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result){
        result->Success(flutter::EncodableValue(TRUE));
    }
    void TtsManager::speakText(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result){
        result->Success(flutter::EncodableValue(TRUE));
    }
    void TtsManager::playVoice(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result){
        result->Success(flutter::EncodableValue(TRUE));
    }
    void TtsManager::generateVoice(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result){
        result->Success(flutter::EncodableValue(TRUE));
    }
    void TtsManager::dispose(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result){
        result->Success(flutter::EncodableValue(TRUE));
    }
}