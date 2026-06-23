#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OpenCVDraftImageMatcher : NSObject

+ (double)hsvDistanceBetweenImage:(UIImage *)firstImage
                       secondImage:(UIImage *)secondImage;

+ (double)combinedDistanceBetweenImage:(UIImage *)firstImage
                            secondImage:(UIImage *)secondImage;

@end

NS_ASSUME_NONNULL_END
