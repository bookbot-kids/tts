#include "tts_manager.h"

// CppFlow headers
#include "cppflow/cppflow.h"

// C++ headers
#include <iostream>

// AudioFile headers
#include "AudioFile.hpp"

#include <xaudio2.h>
#include <vector>

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
        initialized = false;
    }

    TtsManager::~TtsManager() {
    }

    IXAudio2* InitializeXAudio2() {
        IXAudio2* xAudio2 = nullptr;
        HRESULT hr = XAudio2Create(&xAudio2, 0, XAUDIO2_DEFAULT_PROCESSOR);
        if (FAILED(hr)) {
            // Error handling
            return nullptr;
        }
        return xAudio2;
    }

    void PlayAudioData(const std::vector<float>& audioData, int sampleRate, int numChannels) {
        IXAudio2* xAudio2 = InitializeXAudio2();
        if (!xAudio2) {
            return;
        }

        WAVEFORMATEX waveFormat;
        waveFormat.wFormatTag = WAVE_FORMAT_IEEE_FLOAT;
        waveFormat.nChannels = static_cast<WORD>(numChannels);
        waveFormat.nSamplesPerSec = sampleRate;
        waveFormat.wBitsPerSample = sizeof(float) * 8;
        waveFormat.nBlockAlign = waveFormat.nChannels * waveFormat.wBitsPerSample / 8;
        waveFormat.nAvgBytesPerSec = waveFormat.nSamplesPerSec * waveFormat.nBlockAlign;
        waveFormat.cbSize = 0;

        IXAudio2MasteringVoice* masteringVoice = nullptr;
        HRESULT hr = xAudio2->CreateMasteringVoice(&masteringVoice);
        if (FAILED(hr)) {
            // Error handling
            xAudio2->Release();
            return;
        }

        IXAudio2SourceVoice* sourceVoice = nullptr;
        hr = xAudio2->CreateSourceVoice(&sourceVoice, &waveFormat);
        if (FAILED(hr)) {
            // Error handling
            masteringVoice->DestroyVoice();
            xAudio2->Release();
            return;
        }

        XAUDIO2_BUFFER buffer = { 0 };
        buffer.AudioBytes = static_cast<UINT32>(audioData.size() * sizeof(float));
        buffer.pAudioData = reinterpret_cast<const BYTE*>(audioData.data());
        buffer.Flags = XAUDIO2_END_OF_STREAM;
        buffer.LoopCount = XAUDIO2_NO_LOOP_REGION;

        hr = sourceVoice->SubmitSourceBuffer(&buffer);
        if (FAILED(hr)) {
            // Error handling
            sourceVoice->DestroyVoice();
            masteringVoice->DestroyVoice();
            xAudio2->Release();
            return;
        }

        hr = sourceVoice->Start(0);
        if (FAILED(hr)) {
            // Error handling
            sourceVoice->DestroyVoice();
            masteringVoice->DestroyVoice();
            xAudio2->Release();
            return;
        }

        // Wait for the audio to finish playing
        XAUDIO2_VOICE_STATE state;
        do {
            sourceVoice->GetState(&state);
            Sleep(10);
        } while (state.BuffersQueued > 0);

        // Clean up
        sourceVoice->DestroyVoice();
        masteringVoice->DestroyVoice();
        xAudio2->Release();
    }

    void TtsManager::initModel(std::string fastSpeechModel, std::string melganModel) {
        if (!initialized) {
            lightspeech = std::make_unique<cppflow::model>(fastSpeechModel);
            mbmelgan = std::make_unique<cppflow::model>(melganModel);
            initialized = true;
        }       
    }

    void TtsManager::speakText(const flutter::EncodableMap* args, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result){
        auto fastSpeechModel_it = (args->find(flutter::EncodableValue("fastSpeechModel")))->second;
        auto melganModel_it = (args->find(flutter::EncodableValue("melganModel")))->second;
        std::string fastSpeechModel = std::get<std::string>(fastSpeechModel_it);
        std::string melganModel = std::get<std::string>(melganModel_it);
        initModel(fastSpeechModel, melganModel);

        auto inputIds_it = (args->find(flutter::EncodableValue("inputIds")))->second;
        auto speed_it = (args->find(flutter::EncodableValue("speed")))->second;
        auto speakerId_it = (args->find(flutter::EncodableValue("speakerId")))->second;
        auto sampleRate_it = (args->find(flutter::EncodableValue("sampleRate")))->second;
        auto hopSize_it = (args->find(flutter::EncodableValue("hopSize")))->second;
        auto requestId_it = (args->find(flutter::EncodableValue("requestId")))->second;

        std::vector<int64_t> inputIds = std::get<std::vector<int64_t>>(inputIds_it);
        double speed = std::get<double>(speed_it);
        std::int32_t speaker = std::get<std::int32_t>(speakerId_it);
        std::int32_t sampleRate = std::get<std::int32_t>(sampleRate_it);

        // This is the shape of the input IDs, our equivalent to tf.expand_dims.
        std::vector<int64_t> InputIDShape = { 1, (int64_t)inputIds.size() };

        // Define the tensors
        cppflow::tensor input_ids{inputIds, InputIDShape};
        cppflow::tensor energy_ratios{1.f};
        cppflow::tensor f0_ratios{1.f};
        
        // change speaker index here
        cppflow::tensor speaker_ids{speaker};
        cppflow::tensor speed_ratios{speed};

        // Vector of input tensors
        TensorVec inputs = { {"serving_default_input_ids:0", input_ids},
                            {"serving_default_speaker_ids:0", speaker_ids},
                            {"serving_default_energy_ratios:0", energy_ratios},
                            {"serving_default_f0_ratios:0", f0_ratios},
                            {"serving_default_speed_ratios:0", speed_ratios} };

        // infer; LightSpeech returns 3 outputs: (mel, duration, pitch)
        auto outputs = (*lightspeech)(inputs, { "StatefulPartitionedCall:0", "StatefulPartitionedCall:1", "StatefulPartitionedCall:2" });
        // NOTE: FastSpeech2 returns >3 outputs!

        TFTensor<float> mel_spec = CopyTensor<float>(outputs[0]);
        TFTensor<int32_t> durations = CopyTensor<int32_t>(outputs[1]);

        // prepare mel spectrograms for input
        cppflow::tensor input_mels{mel_spec.Data, mel_spec.Shape};
        // infer
        auto out_audio = (*mbmelgan)({ {"serving_default_mels:0", input_mels} }, { "StatefulPartitionedCall:0" })[0];
        TFTensor<float> audio_tensor = CopyTensor<float>(out_audio);

        // play audio
        const std::vector<float> audioData = audio_tensor.Data;
        PlayAudioData(audioData, sampleRate, 1);
        result->Success(flutter::EncodableValue(TRUE));
    }

    void TtsManager::playVoice(const flutter::EncodableMap* args, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result){
        auto fastSpeechModel_it = (args->find(flutter::EncodableValue("fastSpeechModel")))->second;
        auto melganModel_it = (args->find(flutter::EncodableValue("melganModel")))->second;
        std::string fastSpeechModel = std::get<std::string>(fastSpeechModel_it);
        std::string melganModel = std::get<std::string>(melganModel_it);
        initModel(fastSpeechModel, melganModel);
        result->Success(flutter::EncodableValue(TRUE));
    }

    void TtsManager::generateVoice(const flutter::EncodableMap* args, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result){
        auto fastSpeechModel_it = (args->find(flutter::EncodableValue("fastSpeechModel")))->second;
        auto melganModel_it = (args->find(flutter::EncodableValue("melganModel")))->second;
        std::string fastSpeechModel = std::get<std::string>(fastSpeechModel_it);
        std::string melganModel = std::get<std::string>(melganModel_it);
        initModel(fastSpeechModel, melganModel);
        result->Success(flutter::EncodableValue(TRUE));
    }

    void TtsManager::dispose(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        initialized = false;
        lightspeech.reset();
        mbmelgan.reset();
        result->Success(flutter::EncodableValue(TRUE));
    }
}