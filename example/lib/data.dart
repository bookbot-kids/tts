/// Default sample text for English TTS testing.
// Reference: 'hello world' → IPA 'h ə l oʊ  w ɝ r l d' → IDs '53 20 64 70 91 45 64 37'
const defaultEnText =
    'library aback ables hello world may then them single they she go do it love me so much join us';

/// Default sample text for Indonesian TTS testing.
const defaultIdText =
    'Saat kamu mengetuk kamu akan secara otomatis mengubah halaman ketika kamu selesai kecuali kamu';

/// Default sample text for Swahili TTS testing.
const defaultSwText =
    'ting ajabu chakula vitabu hatafuti panya kutafuta hiki hivyo siwezi ana mkubwa';

/// Pre-built input ID sequences for performance benchmarking.
///
/// Each inner list is a ready-to-use sequence of phoneme token IDs that
/// can be fed directly to the ONNX model without IPA lookup, allowing
/// consistent measurement of inference time.
final testInputIds = [
  [55, 3, 27, 69, 36, 19, 3, 40, 45, 33, 3, 32, 33, 63, 50, 24, 4, 3],
  [
    37,
    56,
    10,
    3,
    40,
    45,
    33,
    3,
    37,
    62,
    38,
    3,
    45,
    3,
    22,
    69,
    29,
    3,
    32,
    33,
    63,
    50,
    24,
    4,
    3
  ],
  [37, 66, 27, 3, 19, 69, 29, 4, 3],
  [63, 32, 45, 28, 12, 3],
  [37, 69, 33, 3, 45, 3, 48, 50, 57, 33, 3, 32, 33, 63, 50, 24, 4, 3]
];
