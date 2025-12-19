//
//  OpenCVWrapper.h
//  Objective-C Bridge for OpenCV
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OpenCVWrapper : NSObject

// Image Enhancement (Pre-OCR)
+ (UIImage *)enhanceImageForOCR:(UIImage *)image;

// Text-Seeded Balloon Detection
+ (nullable NSValue *)expandTextRegionToBalloon:(UIImage *)image
                                       textRect:(CGRect)textRect;

// Preprocessing Pipeline (Legacy)
+ (UIImage *)preprocessImageForDetection:(UIImage *)image;
+ (UIImage *)cannyEdgeDetection:(UIImage *)image
                   lowThreshold:(double)low
                  highThreshold:(double)high;
+ (UIImage *)morphologicalClose:(UIImage *)image kernelSize:(int)size;

@end

NS_ASSUME_NONNULL_END
