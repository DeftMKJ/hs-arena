#import <UIKit/UIKit.h>

#if TARGET_OS_MACCATALYST

NS_ASSUME_NONNULL_BEGIN

@interface OpenCVDraftImageMatcher : NSObject

+ (double)hsvDistanceBetweenImage:(UIImage *)firstImage
                       secondImage:(UIImage *)secondImage;

+ (double)combinedDistanceBetweenImage:(UIImage *)firstImage
                            secondImage:(UIImage *)secondImage;

@end

NS_ASSUME_NONNULL_END

#endif
