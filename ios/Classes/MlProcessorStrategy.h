@protocol ProcessorStrategyDelegate <NSObject>
- (NSURL*)urlFor:(NSString*)imagePath;
@end

@interface MlProcessorStrategy : NSObject
 + (MlProcessorStrategy*)shared;
@property (nonatomic, weak) id<ProcessorStrategyDelegate> delegate;
@end