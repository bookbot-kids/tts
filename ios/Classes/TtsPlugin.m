#import "TtsPlugin.h"
#if __has_include(<tts/tts-Swift.h>)
#import <tts/tts-Swift.h>
#else
// Support project import fallback if the generated compatibility header
// is not copied when this plugin is created as a library.
// https://forums.swift.org/t/swift-static-libraries-dont-copy-generated-objective-c-header/19816
#import "tts-Swift.h"
#endif

@implementation TtsPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftTtsPlugin registerWithRegistrar:registrar];
}
@end
