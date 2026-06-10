#!/usr/bin/env python3
"""
Sherpa-ONNX PocketTTS inference with energy-based character-level timestamp extraction.

This script demonstrates how to use sherpa-onnx Python API for PocketTTS
with integrated character-level timestamp extraction using energy-based segmentation.

Usage:
    python pocket-tts-sherpa-onnx-with-timestamps.py --text "Hello world" --output output.wav

Requirements:
    pip install sherpa-onnx librosa scipy numpy

Model Download:
    wget https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/sherpa-onnx-pocket-tts-int8-2026-01-26.tar.bz2
    tar xvf sherpa-onnx-pocket-tts-int8-2026-01-26.tar.bz2
"""

import argparse
import json
import time
from dataclasses import dataclass
from pathlib import Path
from typing import List, Tuple

import librosa
import numpy as np
import sherpa_onnx
import scipy.io.wavfile as wav


@dataclass
class CharacterTiming:
    """Represents timing information for a single character."""
    char: str
    start_time: float
    end_time: float
    char_index: int


class EnergyBasedTimestampExtractor:
    """
    Extract character-level timestamps from audio using energy-based segmentation.
    Works with pure audio output from sherpa-onnx, no model access needed.
    """
    
    def __init__(self, 
                 frame_ms: float = 20.0,
                 energy_threshold_factor: float = 0.1,
                 min_segment_duration: float = 0.05):
        """
        Initialize the energy-based timestamp extractor.
        
        Args:
            frame_ms: Frame size in milliseconds for energy calculation
            energy_threshold_factor: Factor for energy threshold (relative to max)
            min_segment_duration: Minimum duration for a speech segment in seconds
        """
        self.frame_ms = frame_ms
        self.energy_threshold_factor = energy_threshold_factor
        self.min_segment_duration = min_segment_duration
    
    def extract_energy_profile(self, audio: np.ndarray, sample_rate: int) -> Tuple[np.ndarray, np.ndarray]:
        """
        Extract energy profile from audio.
        
        Returns:
            energy: RMS energy per frame
            timestamps: Timestamp for each frame
        """
        frame_length = int(sample_rate * self.frame_ms / 1000)
        hop_length = frame_length // 2  # 50% overlap
        
        # Calculate RMS energy
        rms = librosa.feature.rms(y=audio, frame_length=frame_length, hop_length=hop_length)[0]
        
        # Calculate timestamps for each frame
        timestamps = librosa.frames_to_time(np.arange(len(rms)), sr=sample_rate, hop_length=hop_length)
        
        return rms, timestamps
    
    def detect_speech_segments(self, energy: np.ndarray, timestamps: np.ndarray) -> List[Tuple[float, float]]:
        """
        Detect speech segments from energy profile.
        
        Returns:
            List of (start_time, end_time) tuples for speech segments
        """
        if len(energy) < 3:
            return [(0, timestamps[-1])] if len(timestamps) > 0 else []
        
        # Dynamic threshold based on energy statistics
        energy_percentile = np.percentile(energy, 30)
        energy_max = np.max(energy)
        threshold = energy_percentile + self.energy_threshold_factor * (energy_max - energy_percentile)
        
        # Find speech regions
        is_speech = energy > threshold
        
        # Find segment boundaries
        segments = []
        in_segment = False
        start_time = 0
        
        for i, (is_active, time) in enumerate(zip(is_speech, timestamps)):
            if is_active and not in_segment:
                start_time = time
                in_segment = True
            elif not is_active and in_segment:
                if time - start_time >= self.min_segment_duration:
                    segments.append((start_time, time))
                in_segment = False
        
        # Handle last segment
        if in_segment:
            segments.append((start_time, timestamps[-1]))
        
        # If no segments found, use the entire audio
        if not segments:
            segments = [(0, timestamps[-1])]
        
        return segments
    
    def align_text_to_segments(self, text: str, segments: List[Tuple[float, float]]) -> List[CharacterTiming]:
        """
        Align text characters to speech segments.
        
        Args:
            text: Input text
            segments: List of (start, end) time tuples
            
        Returns:
            List of CharacterTiming objects
        """
        # Remove excessive whitespace and split into words
        words = text.split()
        if not words:
            return []
        
        # Calculate total duration for non-space characters
        total_duration = sum(end - start for start, end in segments)
        
        # Count non-space characters
        char_count = sum(len(word) for word in words)
        if char_count == 0:
            return []
        
        # Base duration per character
        base_char_duration = total_duration / (char_count + len(words) - 1)  # Include space timing
        
        # Distribute characters across segments
        timings = []
        current_time = segments[0][0] if segments else 0
        segment_idx = 0
        segment_start, segment_end = segments[segment_idx] if segments else (0, 1)
        
        char_index = 0
        
        for word_idx, word in enumerate(words):
            # Add space before word (except first word)
            if word_idx > 0:
                space_duration = base_char_duration * 0.3  # Spaces are shorter
                
                # Check if we need to move to next segment
                if current_time + space_duration > segment_end and segment_idx + 1 < len(segments):
                    segment_idx += 1
                    segment_start, segment_end = segments[segment_idx]
                    current_time = segment_start
                
                timings.append(CharacterTiming(
                    char=' ',
                    start_time=current_time,
                    end_time=min(current_time + space_duration, segment_end),
                    char_index=char_index
                ))
                current_time = min(current_time + space_duration, segment_end)
                char_index += 1
            
            # Add characters in word
            for char in word:
                char_duration = base_char_duration
                
                # Check if we need to move to next segment
                if current_time + char_duration > segment_end and segment_idx + 1 < len(segments):
                    segment_idx += 1
                    segment_start, segment_end = segments[segment_idx]
                    current_time = segment_start
                
                timings.append(CharacterTiming(
                    char=char,
                    start_time=current_time,
                    end_time=min(current_time + char_duration, segment_end),
                    char_index=char_index
                ))
                current_time = min(current_time + char_duration, segment_end)
                char_index += 1
        
        # Add punctuation and remaining characters
        remaining_text = text[char_index:]
        for char in remaining_text:
            if char.isspace():
                continue  # Skip extra spaces
            
            # Punctuation gets minimal duration
            punct_duration = 0.05 if char in '.!?;:,' else base_char_duration
            
            timings.append(CharacterTiming(
                char=char,
                start_time=current_time,
                end_time=current_time + punct_duration,
                char_index=char_index
            ))
            current_time += punct_duration
            char_index += 1
        
        return timings
    
    def extract_timestamps(self, audio: np.ndarray, sample_rate: int, text: str) -> List[CharacterTiming]:
        """
        Main method: Extract character timestamps from audio and text.
        
        Args:
            audio: Audio signal as numpy array
            sample_rate: Sample rate in Hz
            text: Input text
            
        Returns:
            List of CharacterTiming objects
        """
        # Extract energy profile
        energy, frame_timestamps = self.extract_energy_profile(audio, sample_rate)
        
        # Detect speech segments
        segments = self.detect_speech_segments(energy, frame_timestamps)
        
        # Align text to segments
        char_timings = self.align_text_to_segments(text, segments)
        
        return char_timings


class PocketTTSWithTimestamps:
    """
    PocketTTS wrapper with integrated timestamp extraction.
    """
    
    def __init__(self, model_dir: str, reference_audio: str = None):
        """
        Initialize PocketTTS with timestamp support.
        
        Args:
            model_dir: Path to the sherpa-onnx PocketTTS model directory
            reference_audio: Path to reference audio for voice cloning (optional)
        """
        self.model_dir = Path(model_dir)
        
        # Initialize sherpa-onnx TTS
        self.tts_config = sherpa_onnx.OfflineTtsConfig(
            model=sherpa_onnx.OfflineTtsModelConfig(
                pocket=sherpa_onnx.OfflineTtsPocketModelConfig(
                    lm_flow=str(self.model_dir / "lm_flow.int8.onnx"),
                    lm_main=str(self.model_dir / "lm_main.int8.onnx"),
                    encoder=str(self.model_dir / "encoder.onnx"),
                    decoder=str(self.model_dir / "decoder.int8.onnx"),
                    text_conditioner=str(self.model_dir / "text_conditioner.onnx"),
                    vocab_json=str(self.model_dir / "vocab.json"),
                    token_scores_json=str(self.model_dir / "token_scores.json"),
                ),
                num_threads=2,
                provider="cpu",
            )
        )
        
        if not self.tts_config.validate():
            raise ValueError("Invalid sherpa-onnx configuration")
        
        self.tts = sherpa_onnx.OfflineTts(self.tts_config)
        
        # Load reference audio if provided
        self.reference_audio = None
        self.reference_sample_rate = None
        if reference_audio and Path(reference_audio).exists():
            self.reference_audio, self.reference_sample_rate = librosa.load(
                reference_audio, sr=self.tts.sample_rate
            )
        
        # Initialize timestamp extractor
        self.timestamp_extractor = EnergyBasedTimestampExtractor()
    
    def generate(self, text: str, extract_timestamps: bool = True) -> dict:
        """
        Generate speech with optional timestamp extraction.
        
        Args:
            text: Text to synthesize
            extract_timestamps: Whether to extract character timestamps
            
        Returns:
            Dictionary with:
                - audio: Audio samples as numpy array
                - sample_rate: Sample rate in Hz
                - timestamps: List of CharacterTiming objects (if requested)
                - duration: Audio duration in seconds
                - rtf: Real-time factor
        """
        # Setup generation config
        gen_config = sherpa_onnx.GenerationConfig()
        if self.reference_audio is not None:
            gen_config.reference_audio = self.reference_audio
            gen_config.reference_sample_rate = self.reference_sample_rate
        gen_config.num_steps = 10  # Number of denoising steps
        
        # Generate audio
        start_time = time.time()
        audio = self.tts.generate(text, gen_config)
        generation_time = time.time() - start_time
        
        if len(audio.samples) == 0:
            raise RuntimeError("Failed to generate audio")
        
        # Calculate metrics
        audio_duration = len(audio.samples) / audio.sample_rate
        rtf = generation_time / audio_duration if audio_duration > 0 else 0
        
        result = {
            'audio': audio.samples,
            'sample_rate': audio.sample_rate,
            'duration': audio_duration,
            'generation_time': generation_time,
            'rtf': rtf
        }
        
        # Extract timestamps if requested
        if extract_timestamps:
            # Convert samples to numpy array if it's a list
            audio_array = np.array(audio.samples) if isinstance(audio.samples, list) else audio.samples
            timestamps = self.timestamp_extractor.extract_timestamps(
                audio_array, audio.sample_rate, text
            )
            result['timestamps'] = timestamps
        
        return result
    
    def save_audio(self, audio: np.ndarray, sample_rate: int, output_path: str):
        """Save audio to WAV file."""
        # Convert to numpy array if needed
        audio_array = np.array(audio) if isinstance(audio, list) else audio
        # Convert to int16
        audio_int16 = (audio_array * 32767).astype(np.int16)
        wav.write(output_path, sample_rate, audio_int16)
    
    def save_timestamps(self, timestamps: List[CharacterTiming], output_path: str):
        """Save timestamps to JSON file."""
        timestamp_data = [
            {
                'char': t.char,
                'start': t.start_time,
                'end': t.end_time,
                'index': t.char_index
            }
            for t in timestamps
        ]
        
        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(timestamp_data, f, indent=2, ensure_ascii=False)
    
    def print_timestamps(self, text: str, timestamps: List[CharacterTiming]):
        """Print character timestamps in a readable format."""
        print("\nCharacter Timestamps:")
        print("-" * 50)
        print(f"{'Char':<6} {'Start':<8} {'End':<8} {'Duration':<8}")
        print("-" * 50)
        
        for timing in timestamps:
            duration = timing.end_time - timing.start_time
            char_display = repr(timing.char) if timing.char.isspace() else timing.char
            print(f"{char_display:<6} {timing.start_time:>7.3f}s {timing.end_time:>7.3f}s {duration:>7.3f}s")
        
        print("-" * 50)
        print(f"Text: {text}")
        print(f"Total characters: {len(timestamps)}")
        if timestamps:
            print(f"Total duration: {timestamps[-1].end_time:.3f}s")


def main():
    parser = argparse.ArgumentParser(
        description="PocketTTS inference with character-level timestamps using sherpa-onnx"
    )
    parser.add_argument(
        "--model-dir",
        type=str,
        default="sherpa-onnx-pocket-tts-int8-2026-01-26",
        help="Path to sherpa-onnx PocketTTS model directory"
    )
    parser.add_argument(
        "--reference-audio",
        type=str,
        default=None,
        help="Path to reference audio for voice cloning (optional)"
    )
    parser.add_argument(
        "--text",
        type=str,
        default="Hello, this is a test of PocketTTS with character timestamps.",
        help="Text to synthesize"
    )
    parser.add_argument(
        "--output",
        type=str,
        default="output_with_timestamps.wav",
        help="Output audio file path"
    )
    parser.add_argument(
        "--save-timestamps",
        type=str,
        default=None,
        help="Path to save timestamps as JSON (optional)"
    )
    parser.add_argument(
        "--no-timestamps",
        action="store_true",
        help="Disable timestamp extraction"
    )
    
    args = parser.parse_args()
    
    # Check if model directory exists
    if not Path(args.model_dir).exists():
        print(f"Error: Model directory not found: {args.model_dir}")
        print("Please download the model first:")
        print("  wget https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/sherpa-onnx-pocket-tts-int8-2026-01-26.tar.bz2")
        print("  tar xvf sherpa-onnx-pocket-tts-int8-2026-01-26.tar.bz2")
        return 1
    
    # Use default reference audio if not specified
    if args.reference_audio is None:
        default_ref = Path(args.model_dir) / "test_wavs" / "bria.wav"
        if default_ref.exists():
            args.reference_audio = str(default_ref)
            print(f"Using default reference audio: {args.reference_audio}")
    
    # Initialize TTS with timestamps
    print("Initializing PocketTTS...")
    tts = PocketTTSWithTimestamps(args.model_dir, args.reference_audio)
    
    # Generate speech
    print(f"\nGenerating speech for: '{args.text}'")
    result = tts.generate(args.text, extract_timestamps=not args.no_timestamps)
    
    # Save audio
    tts.save_audio(result['audio'], result['sample_rate'], args.output)
    print(f"\nAudio saved to: {args.output}")
    
    # Print generation metrics
    print(f"Duration: {result['duration']:.2f}s")
    print(f"Generation time: {result['generation_time']:.3f}s")
    print(f"RTF (Real-Time Factor): {result['rtf']:.3f}")
    
    # Handle timestamps
    if 'timestamps' in result:
        tts.print_timestamps(args.text, result['timestamps'])
        
        if args.save_timestamps:
            tts.save_timestamps(result['timestamps'], args.save_timestamps)
            print(f"\nTimestamps saved to: {args.save_timestamps}")
    
    return 0


if __name__ == "__main__":
    exit(main())