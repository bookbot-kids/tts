@protocol ProcessorStrategyDelegate <NSObject>
- (void)urlsFor:(NSArray*)models withComplete:(void(^)(NSArray*))onCompleted;
- (void)playBuffer:(NSData*) audioBuffer withSampleRate: (int) sampleRate withCancelled:(BOOL(^)(void))isCancelled withCompleted:(void(^)(void))onCompleted;
@end

@interface MlProcessorStrategy : NSObject
 + (MlProcessorStrategy*)shared;
@property (nonatomic, weak) id<ProcessorStrategyDelegate> delegate;
@end
