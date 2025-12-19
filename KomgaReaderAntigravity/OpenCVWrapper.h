//
//  OpenCVWrapper.h
//  Objective-C++ Bridge for OpenCV
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OpenCVWrapper : NSObject

/// Preprocesses image for balloon detection: Grayscale -> Blur -> Canny -> Morphological Ops
+ (UIImage *)preprocessImageForDetection:(UIImage *)image;

/// Detects contours in preprocessed image and returns bounding boxes (normalized 0-1)
+ (NSArray<NSValue *> *)detectBalloonContours:(UIImage *)image;

/// Applies Canny edge detection
+ (UIImage *)cannyEdgeDetection:(UIImage *)image 
                   lowThreshold:(double)low 
                  highThreshold:(double)high;

/// Applies morphological closing (dilate then erode) to close gaps
+ (UIImage *)morphologicalClose:(UIImage *)image 
                     kernelSize:(int)size;

@end

NS_ASSUME_NONNULL_END
