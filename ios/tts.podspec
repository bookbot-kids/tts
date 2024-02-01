#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint tts.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'tts'
  s.version          = '1.0.0'
  s.summary          = 'Text to speech plugin'
  s.description      = <<-DESC
A text to speech flutter plugin
                       DESC
  s.homepage         = 'https://www.bookbotkids.com/'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Bookbot' => 'team@bookbotkids.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'
  s.static_framework = true

  s.dependency 'onnxruntime-objc', '~> 1.16.3'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end