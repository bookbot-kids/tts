#import "MlProcessorStrategy.h"

@implementation MlProcessorStrategy
static MlProcessorStrategy *_shared = nil;

+ (MlProcessorStrategy*)shared {
   static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _shared = [[self alloc] init];

    });

    return _shared;
}


@end