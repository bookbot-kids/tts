#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint tts.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'tts'
  s.version          = '0.0.1'
  s.summary          = 'Text to speech flutter.'
  s.description      = <<-DESC
Text to speech flutter project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '11.0'
  s.static_framework = true

  s.dependency 'TensorFlowLiteSwift', '~> 2.10', :subspecs => ['CoreML', 'Metal']
  s.dependency 'TensorFlowLiteSelectTfOps', '~> 2.10'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
  s.xcconfig = {
    'USER_HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_ROOT}/Headers/Private" "${PODS_ROOT}/Headers/Private/tflite" "${PODS_ROOT}/Headers/Public" "${PODS_ROOT}/Headers/Public/Flutter" "${PODS_ROOT}/Headers/Public/TensorFlowLite/tensorflow_lite" "${PODS_ROOT}/Headers/Public/tflite" "${PODS_ROOT}/TensorFlowLite/Frameworks/tensorflow_lite.framework/Headers" "${PODS_ROOT}/TensorFlowLiteC/Frameworks/TensorFlowLiteC.framework/Headers" "${PODS_ROOT}/TensorFlowLiteSelectTfOps/Frameworks/TensorFlowLiteSelectTfOps.framework"',
    'OTHER_LDFLAGS' => '$(inherited) -force_load $(SRCROOT)/Pods/TensorFlowLiteSelectTfOps/Frameworks/TensorFlowLiteSelectTfOps.xcframework/ios-arm64/TensorFlowLiteSelectTfOps.framework/TensorFlowLiteSelectTfOps' 
  }
end