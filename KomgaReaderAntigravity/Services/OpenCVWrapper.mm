//
//  OpenCVWrapper.mm
//  Objective-C++ Implementation
//

#import "OpenCVWrapper.h"
// Don't include opencv.hpp to avoid stitching module conflicts with Apple's NO
// macro
#import <opencv2/core.hpp>
#import <opencv2/imgcodecs.hpp>
#import <opencv2/imgproc.hpp>

// Don't use 'using namespace cv' to avoid conflicts with CoreGraphics
// Instead, explicitly prefix OpenCV types with cv::

@implementation OpenCVWrapper

#pragma mark - Helper: UIImage <-> cv::Mat

+ (cv::Mat)cvMatFromUIImage:(UIImage *)image {
  CGColorSpaceRef colorSpace = CGImageGetColorSpace(image.CGImage);
  CGFloat cols = image.size.width;
  CGFloat rows = image.size.height;

  cv::Mat cvMat(rows, cols, CV_8UC4); // 8 bits per component, 4 channels (RGBA)

  CGContextRef contextRef = CGBitmapContextCreate(
      cvMat.data, cols, rows, 8, cvMat.step[0], colorSpace,
      (CGBitmapInfo)kCGImageAlphaNoneSkipLast |
          (CGBitmapInfo)kCGBitmapByteOrderDefault);

  CGContextDrawImage(contextRef, CGRectMake(0, 0, cols, rows), image.CGImage);
  CGContextRelease(contextRef);

  return cvMat;
}

+ (UIImage *)UIImageFromCVMat:(cv::Mat)cvMat {
  NSData *data = [NSData dataWithBytes:cvMat.data
                                length:cvMat.elemSize() * cvMat.total()];

  CGColorSpaceRef colorSpace;
  CGBitmapInfo bitmapInfo;

  if (cvMat.elemSize() == 1) {
    colorSpace = CGColorSpaceCreateDeviceGray();
    bitmapInfo = (CGBitmapInfo)kCGImageAlphaNone |
                 (CGBitmapInfo)kCGBitmapByteOrderDefault;
  } else {
    colorSpace = CGColorSpaceCreateDeviceRGB();
    bitmapInfo =
        (CGBitmapInfo)kCGBitmapByteOrder32Little |
        (cvMat.elemSize() == 3 ? (CGBitmapInfo)kCGImageAlphaNone
                               : (CGBitmapInfo)kCGImageAlphaNoneSkipFirst);
  }

  CGDataProviderRef provider =
      CGDataProviderCreateWithCFData((__bridge CFDataRef)data);

  CGImageRef imageRef = CGImageCreate(
      cvMat.cols, cvMat.rows, 8, 8 * cvMat.elemSize(), cvMat.step[0],
      colorSpace, bitmapInfo, provider, NULL, false, kCGRenderingIntentDefault);

  UIImage *finalImage = [UIImage imageWithCGImage:imageRef];

  CGImageRelease(imageRef);
  CGDataProviderRelease(provider);
  CGColorSpaceRelease(colorSpace);

  return finalImage;
}

#pragma mark - Image Enhancement (Pre-OCR)

+ (UIImage *)enhanceImageForOCR:(UIImage *)image {
  cv::Mat src = [self cvMatFromUIImage:image];
  cv::Mat gray, enhanced;

  // 1. Grayscale
  cv::cvtColor(src, gray, cv::COLOR_BGRA2GRAY);

  // 2. Adaptive histogram equalization (CLAHE) for better contrast
  cv::Ptr<cv::CLAHE> clahe = cv::createCLAHE(2.0, cv::Size(8, 8));
  clahe->apply(gray, enhanced);

  // 3. Slight sharpening
  cv::Mat blurred;
  cv::GaussianBlur(enhanced, blurred, cv::Size(0, 0), 3);
  cv::addWeighted(enhanced, 1.5, blurred, -0.5, 0, enhanced);

  return [self UIImageFromCVMat:enhanced];
}

#pragma mark - Text-Seeded Balloon Detection

+ (nullable NSValue *)expandTextRegionToBalloon:(UIImage *)image
                                       textRect:(CGRect)textRect {
  cv::Mat src = [self cvMatFromUIImage:image];
  cv::Mat gray, binary, dilated;

  // 1. Grayscale
  cv::cvtColor(src, gray, cv::COLOR_BGRA2GRAY);

  // 2. Adaptive threshold to get binary image
  // Smaller block size and lower C value for more conservative thresholding
  cv::adaptiveThreshold(gray, binary, 255, cv::ADAPTIVE_THRESH_GAUSSIAN_C,
                        cv::THRESH_BINARY_INV, 11, 5);

  // 3. Dilate to connect text to balloon borders
  // MUCH SMALLER kernel - only expand locally around text
  cv::Mat kernel = cv::getStructuringElement(cv::MORPH_ELLIPSE, cv::Size(7, 7));
  cv::dilate(binary, dilated, kernel, cv::Point(-1, -1), 2); // 2 iterations

  // 4. Find contours
  std::vector<std::vector<cv::Point>> contours;
  cv::findContours(dilated, contours, cv::RETR_EXTERNAL,
                   cv::CHAIN_APPROX_SIMPLE);

  // 5. Convert textRect to pixel coordinates
  int imgWidth = src.cols;
  int imgHeight = src.rows;

  // Vision coordinates: (0,0) at bottom-left, normalized
  // Convert to OpenCV: (0,0) at top-left, pixels
  cv::Point textCenter((textRect.origin.x + textRect.size.width / 2) * imgWidth,
                       (1.0 - textRect.origin.y - textRect.size.height / 2) *
                           imgHeight);

  NSLog(@"[OpenCV] Text center: (%d, %d) in image (%d x %d)", textCenter.x,
        textCenter.y, imgWidth, imgHeight);

  // 6. Find contour containing text center
  for (const auto &contour : contours) {
    if (cv::pointPolygonTest(contour, textCenter, false) >= 0) {
      // Found the balloon!
      cv::Rect rect = cv::boundingRect(contour);
      double area = cv::contourArea(contour);

      NSLog(@"[OpenCV] Found balloon: area=%.0f, rect=(%d,%d,%d,%d)", area,
            rect.x, rect.y, rect.width, rect.height);

      // Filter: must be larger than text and reasonable size
      // Adjusted: 500 - 200000 pixels (more realistic for dilated text regions)
      if (area < 500 || area > 200000) {
        NSLog(@"[OpenCV] Balloon filtered by area (%.0f)", area);
        continue;
      }

      // Normalize back to Vision coordinates
      CGRect normalizedRect = CGRectMake(
          (CGFloat)rect.x / imgWidth,
          1.0 - ((CGFloat)(rect.y + rect.height) / imgHeight),
          (CGFloat)rect.width / imgWidth, (CGFloat)rect.height / imgHeight);

      return [NSValue valueWithCGRect:normalizedRect];
    }
  }

  NSLog(@"[OpenCV] No balloon found for text region");
  return nil;
}

#pragma mark - Legacy Preprocessing Pipeline

+ (cv::Mat)preprocessImageForDetectionMat:(UIImage *)image {
  cv::Mat src = [self cvMatFromUIImage:image];
  cv::Mat gray, blurred, edges, closed;

  // 1. Grayscale
  cv::cvtColor(src, gray, cv::COLOR_BGRA2GRAY);

  // 2. Gaussian Blur (reduce noise) - Moderate blur
  cv::GaussianBlur(gray, blurred, cv::Size(5, 5), 0);

  // 3. Canny Edge Detection - LOWER thresholds to detect balloon edges
  cv::Canny(blurred, edges, 30, 90);

  // 4. Morphological Closing (close gaps in contours) - Larger kernel to
  // connect edges
  cv::Mat kernel =
      cv::getStructuringElement(cv::MORPH_ELLIPSE, cv::Size(15, 15));
  cv::morphologyEx(edges, closed, cv::MORPH_CLOSE, kernel);

  return closed;
}

+ (UIImage *)preprocessImageForDetection:(UIImage *)image {
  cv::Mat processed = [self preprocessImageForDetectionMat:image];
  return [self UIImageFromCVMat:processed];
}

+ (UIImage *)cannyEdgeDetection:(UIImage *)image
                   lowThreshold:(double)low
                  highThreshold:(double)high {
  cv::Mat src = [self cvMatFromUIImage:image];
  cv::Mat gray, edges;

  if (src.channels() > 1) {
    cv::cvtColor(src, gray, cv::COLOR_BGR2GRAY);
  } else {
    gray = src;
  }

  cv::Canny(gray, edges, low, high);

  return [self UIImageFromCVMat:edges];
}

+ (UIImage *)morphologicalClose:(UIImage *)image kernelSize:(int)size {
  cv::Mat src = [self cvMatFromUIImage:image];
  cv::Mat closed;

  cv::Mat kernel =
      cv::getStructuringElement(cv::MORPH_ELLIPSE, cv::Size(size, size));
  cv::morphologyEx(src, closed, cv::MORPH_CLOSE, kernel);

  return [self UIImageFromCVMat:closed];
}

#pragma mark - Contour Detection

+ (NSArray<NSValue *> *)detectBalloonContours:(UIImage *)image {
  // Preprocess - now returns cv::Mat directly (CV_8UC1 grayscale)
  cv::Mat processed = [self preprocessImageForDetectionMat:image];

  // Find contours
  std::vector<std::vector<cv::Point>> contours;
  std::vector<cv::Vec4i> hierarchy;
  cv::findContours(processed, contours, hierarchy, cv::RETR_EXTERNAL,
                   cv::CHAIN_APPROX_SIMPLE);

  NSLog(@"[OpenCV] Found %lu total contours", contours.size());

  NSMutableArray<NSValue *> *balloonRects = [NSMutableArray array];

  CGFloat width = image.size.width;
  CGFloat height = image.size.height;

  int filteredCount = 0;

  for (const auto &contour : contours) {
    // Calculate bounding box
    cv::Rect rect = cv::boundingRect(contour);

    // Filter by area - 2000 to 100000 pixels (realistic balloon sizes)
    double area = cv::contourArea(contour);
    if (area < 2000) {
      NSLog(@"[OpenCV] Filtered (too small): area=%.0f", area);
      filteredCount++;
      continue;
    }
    if (area > 100000) {
      NSLog(@"[OpenCV] Filtered (too large): area=%.0f", area);
      filteredCount++;
      continue;
    }

    // Filter by aspect ratio - Balloons are roughly square to rectangular
    double aspectRatio = (double)rect.width / rect.height;
    if (aspectRatio < 0.2 || aspectRatio > 5.0) {
      NSLog(@"[OpenCV] Filtered (bad aspect): area=%.0f, aspect=%.2f", area,
            aspectRatio);
      filteredCount++;
      continue;
    }

    // REMOVED solidity filter - too restrictive for irregular balloon shapes

    // Normalize to 0-1
    CGRect normalizedRect =
        CGRectMake(rect.x / width, rect.y / height, rect.width / width,
                   rect.height / height);

    NSLog(@"[OpenCV] Balloon found: area=%.0f, aspect=%.2f, "
          @"rect={%.2f,%.2f,%.2f,%.2f}",
          area, aspectRatio, normalizedRect.origin.x, normalizedRect.origin.y,
          normalizedRect.size.width, normalizedRect.size.height);

    [balloonRects addObject:[NSValue valueWithCGRect:normalizedRect]];
  }

  NSLog(@"[OpenCV] Detected %lu balloons (filtered out %d)", balloonRects.count,
        filteredCount);

  return balloonRects;
}

@end
