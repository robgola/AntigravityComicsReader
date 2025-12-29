//
//  OpenCVWrapper.h
//  Objective-C Bridge for OpenCV
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OpenCVBalloonResult : NSObject
@property(nonatomic, strong) UIImage *markedImage;
@property(nonatomic, strong) NSArray<NSValue *> *balloonRects; // CGRects
@property(nonatomic, strong)
    NSArray<NSArray<NSValue *> *> *contours; // Array of Arrays of CGPoint
@end

@interface OpenCVWrapper : NSObject

// v4.0: Marker Strategy (Legacy - Kept for reference or future toggling)
+ (OpenCVBalloonResult *)detectAndMarkBalloons:(UIImage *)image;

// v5.0: Gemini-Guided GrabCut
+ (NSArray<NSValue *> *)refinedBalloonContour:(UIImage *)image
                                     textRect:(CGRect)rect;

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
