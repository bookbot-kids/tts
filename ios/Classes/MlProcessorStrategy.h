@protocol ProcessorStrategyDelegate <NSObject>
- (NSURL*)urlFor:(NSString*)imagePath;
- (void)playBuffer:(NSData*) audioBuffer;
@end

@interface MlProcessorStrategy : NSObject
 + (MlProcessorStrategy*)shared;
@property (nonatomic, weak) id<ProcessorStrategyDelegate> delegate;
@end
