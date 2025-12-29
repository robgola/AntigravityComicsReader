//
//  OpenCVWrapper.mm
//  Objective-C++ Implementation
//

#import "OpenCVWrapper.h"
#import <UIKit/UIKit.h> // Ensure UIKit is imported

// Standard C++ Library
#include <algorithm>
#include <string>
#include <vector>

// OpenCV
#import <opencv2/core.hpp>
#import <opencv2/imgcodecs.hpp>
#import <opencv2/imgproc.hpp>

// Don't use 'using namespace cv' to avoid conflicts with CoreGraphics
// Instead, explicitly prefix OpenCV types with cv::
// And namespace std for vector/string

@implementation OpenCVBalloonResult
@end

@implementation OpenCVWrapper

// Helper struct for sorting
struct BalloonContour {
  int id;
  cv::Rect rect;
  std::vector<cv::Point> contour;
  cv::Point center;
};

#pragma mark - Marker Strategy v4.0

+ (OpenCVBalloonResult *)detectAndMarkBalloons:(UIImage *)image {
  // 1. Setup
  cv::Mat src = [self cvMatFromUIImage:image];
  // Create a copy for drawing the markers (to be sent to Gemini)
  cv::Mat markedMat = src.clone();

  // 2. Preprocess
  cv::Mat gray, blurred, binary;
  cv::cvtColor(src, gray, cv::COLOR_BGRA2GRAY);
  cv::GaussianBlur(gray, blurred, cv::Size(5, 5), 0);

  // Strategy: Global Threshold + Morphological Operations + Contour Hierarchy
  // Threshold 180: Supports vintage/yellowed paper while ignoring dark art.
  // We use THRESH_BINARY to get "White Regions".
  cv::threshold(blurred, binary, 180, 255, cv::THRESH_BINARY);

  // Clean up
  cv::Mat kernel = cv::getStructuringElement(cv::MORPH_ELLIPSE, cv::Size(5, 5));
  cv::morphologyEx(binary, binary, cv::MORPH_OPEN, kernel);
  cv::morphologyEx(binary, binary, cv::MORPH_CLOSE,
                   kernel); // Close small gaps in text or lines

  // 3. Find Contours - KEY CHANGE: RETR_LIST (or TREE) to find nested balloons
  std::vector<std::vector<cv::Point>> contours;
  std::vector<cv::Vec4i> hierarchy;
  // RETR_TREE allows us to see hierarchy, but LIST is enough if we just filter
  // by properties.
  cv::findContours(binary, contours, hierarchy, cv::RETR_TREE,
                   cv::CHAIN_APPROX_SIMPLE);

  std::vector<BalloonContour> validBalloons;

  CGFloat width = image.size.width;
  CGFloat height = image.size.height;

  // 4. Filter & Collect
  for (size_t i = 0; i < contours.size(); i++) {
    const auto &contour = contours[i];

    // Hierarchy check:
    // hierarchy[i][3] is the parent index.
    // If this contour has a parent, it's inside something.
    // Balloons are often inside Panels. Panels are inside Page.
    // So we shouldn't filter by hierarchy depth blindly.

    double area = cv::contourArea(contour);
    cv::Rect rect = cv::boundingRect(contour);

    // Filter logic
    if (area < 1000)
      continue; // Noise filter (Raised from 500)
    if (area > (src.rows * src.cols * 0.5))
      continue;

    double aspectRatio = (double)rect.width / rect.height;
    if (aspectRatio < 0.3 || aspectRatio > 4.0)
      continue;

    // Solidity Check: Area / ConvexHullArea
    // Balloons are convex or slightly concave (clouds).
    // Jagged balloons might have lower solidity.
    std::vector<cv::Point> hull;
    cv::convexHull(contour, hull);
    double hullArea = cv::contourArea(hull);
    double solidity = area / hullArea;

    if (solidity < 0.75)
      continue; // Raised from 0.6 to exclude jagged/irregular shapes

    // BRIGHTNESS CHECK: Key for filtering out "Blue Hair" or "Skulls"
    cv::Mat mask = cv::Mat::zeros(src.rows, src.cols, CV_8UC1);
    cv::drawContours(mask, contours, (int)i, cv::Scalar(255), cv::FILLED);
    cv::Scalar meanColor = cv::mean(gray, mask);

    // Require very high brightness for the *average* pixel.
    // Real balloons are usually the brightest thing on the page.
    if (meanColor[0] < 215)
      continue; // Raised to 215 (Strict White logic)

    // Calculate center
    cv::Moments m = cv::moments(contour);
    if (m.m00 == 0)
      continue;
    cv::Point center(m.m10 / m.m00, m.m01 / m.m00);

    BalloonContour b;
    b.rect = rect;
    b.contour = contour;
    b.center = center;
    validBalloons.push_back(b);
  }

  // 5. Sort (Reading Order: Top-to-Bottom, Left-to-Right)
  // FIX: Previous comparator violated strict weak ordering (Intransitive
  // equivalence). New Strategy: Robust Bucket Sort.

  // Step A: Sort strictly by Y first
  std::sort(validBalloons.begin(), validBalloons.end(),
            [](const BalloonContour &a, const BalloonContour &b) {
              return a.center.y < b.center.y;
            });

  // Step B: Group into Rows
  std::vector<std::vector<BalloonContour>> rows;
  if (!validBalloons.empty()) {
    rows.push_back({validBalloons[0]});

    for (size_t i = 1; i < validBalloons.size(); ++i) {
      BalloonContour &current = validBalloons[i];
      std::vector<BalloonContour> &lastRow = rows.back();

      // Check if current matches the last row's "Y-level"
      // We use the first element of the row as a reference anchor.
      // 50px tolerance for a "Line" of balloons.
      if (std::abs(current.center.y - lastRow[0].center.y) < 50) {
        lastRow.push_back(current);
      } else {
        rows.push_back({current});
      }
    }
  }

  // Step C: Sort each row by X and flatten back into validBalloons
  validBalloons.clear();
  for (auto &row : rows) {
    std::sort(row.begin(), row.end(),
              [](const BalloonContour &a, const BalloonContour &b) {
                return a.center.x < b.center.x;
              });
    validBalloons.insert(validBalloons.end(), row.begin(), row.end());
  }

  // 6. Draw Markers & Prepare Result
  NSMutableArray<NSValue *> *rectsToCheck = [NSMutableArray array];
  NSMutableArray<NSArray<NSValue *> *> *contoursResult = [NSMutableArray array];

  for (size_t i = 0; i < validBalloons.size(); ++i) {
    BalloonContour &b = validBalloons[i];
    int balloonID = (int)i + 1;

    // A. Draw Red ID
    std::string idStr = std::to_string(balloonID);
    // Position: Center of payload
    // Font settings
    double fontScale = 2.0;
    int thickness = 3;
    int fontFace = cv::FONT_HERSHEY_SIMPLEX;

    // Get text size to center it
    int baseline = 0;
    cv::Size textSize =
        cv::getTextSize(idStr, fontFace, fontScale, thickness, &baseline);
    cv::Point textOrg(b.center.x - textSize.width / 2,
                      b.center.y + textSize.height / 2);

    // Draw Outline (Black) for readability
    cv::putText(markedMat, idStr, textOrg, fontFace, fontScale,
                cv::Scalar(0, 0, 0, 255), thickness + 2);
    // Draw Fill (Red)
    cv::putText(markedMat, idStr, textOrg, fontFace, fontScale,
                cv::Scalar(0, 0, 255, 255), thickness);

    // B. Store Rect (Normalized)
    CGRect normalizedRect = CGRectMake(
        (CGFloat)b.rect.x / width,
        1.0 - ((CGFloat)(b.rect.y + b.rect.height) /
               height), // Vision Coordinate Flip!
                        // Wait, standard UIKit rect for data model?
                        // Vision expects (0,1) at top-left?
                        // No, Vision is Bottom-Left origin.
                        // But UI (SwiftUI) is Top-Left origin.
                        // Let's stick to Top-Left normalized (0-1) for
                        // consistency with current code if possible. Current
                        // code uses Vision rects which are Bottom-Left. But
                        // Gemini returns standard Grid (Top-Left 0,0). Let's
                        // return STANDARD NORMALIZED RECTS (Top-Left origin
                        // 0,0). We will handle conversion in Swift if needed.
                        // Actually, `boundingBox` in DetectedBubble is used for
                        // rendering path. Path is normalized.

        (CGFloat)b.rect.width / width, (CGFloat)b.rect.height / height);

    // Fix Y for Top-Left origin (Standard):
    normalizedRect.origin.y = (CGFloat)b.rect.y / height;
    // Wait, previous code:
    // y: 1.0 - visionBox.maxY
    // Because visionBox is Bottom-Left.
    // OpenCV is Top-Left. So we just divide.

    [rectsToCheck addObject:[NSValue valueWithCGRect:normalizedRect]];

    // C. Store Contour Points (Normalized)
    NSMutableArray<NSValue *> *contourPoints = [NSMutableArray array];
    for (const auto &pt : b.contour) {
      CGPoint p = CGPointMake((CGFloat)pt.x / width,
                              (CGFloat)pt.y / height); // Top-Left Normalized
      [contourPoints addObject:[NSValue valueWithCGPoint:p]];
    }
    [contoursResult addObject:contourPoints];
  }

  OpenCVBalloonResult *result = [[OpenCVBalloonResult alloc] init];
  result.markedImage = [self UIImageFromCVMat:markedMat];
  result.balloonRects = rectsToCheck;
  result.contours = contoursResult;

  return result;
}

#pragma mark - Gemini-Guided GrabCut (v5.0)

+ (NSArray<NSValue *> *)refinedBalloonContour:(UIImage *)image
                                     textRect:(CGRect)rect {
  // 1. Convert UIImage to cv::Mat
  cv::Mat src = [self cvMatFromUIImage:image];
  // GrabCut needs 8-bit 3-channel (BGR)
  cv::Mat src3c;
  cv::cvtColor(src, src3c, cv::COLOR_BGRA2BGR);

  // 2. Setup Masks and Rect
  cv::Mat mask = cv::Mat::zeros(src3c.rows, src3c.cols, CV_8UC1);
  cv::Mat bgModel, fgModel;

  // Convert normalized CGRect to Pixel cv::Rect
  CGFloat w = src3c.cols;
  CGFloat h = src3c.rows;

  // Safety padding: Shrink the box slightly to be safer?
  // Or assume Gemini box is tight?
  // Usually GrabCut expects:
  // Rect contains the object FULLY. Background outside is SURE BACKGROUND.
  // Inside Rect is "Probable Foreground".
  int x = (int)(rect.origin.x * w);
  int y = (int)(rect.origin.y * h);
  int rw = (int)(rect.size.width * w);
  int rh = (int)(rect.size.height * h);

  // Clamp
  x = std::max(0, x);
  y = std::max(0, y);
  rw = std::min((int)src3c.cols - x, rw);
  rh = std::min((int)src3c.rows - y, rh);

  if (rw <= 0 || rh <= 0)
    return @[];

  cv::Rect grabRect(x, y, rw, rh);

  NSLog(@"[OpenCV] GrabCut Rect: %d,%d %dx%d", x, y, rw, rh);

  // 3. Run GrabCut
  // Iterations: 3 is usually enough for simple shapes like balloons using rect
  // initialization
  cv::grabCut(src3c, mask, grabRect, bgModel, fgModel, 3,
              cv::GC_INIT_WITH_RECT);

  // 4. Extract Foreground Mask (GC_FGD = 1, GC_PR_FGD = 3)
  // We want pixels where mask == 1 or 3
  // (mask & 1) will capture 1 and 3.
  cv::Mat binMask;
  mask = mask & 1; // 1 if FG or PR_FG, 0 if BG or PR_BG

  // 5. Find Contours of the Result
  std::vector<std::vector<cv::Point>> contours;
  cv::findContours(mask, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);

  // 6. Select the Best Contour (Largest Area)
  double maxArea = 0;
  int maxIdx = -1;

  for (size_t i = 0; i < contours.size(); i++) {
    double area = cv::contourArea(contours[i]);
    if (area > maxArea) {
      maxArea = area;
      maxIdx = (int)i;
    }
  }

  if (maxIdx == -1)
    return @[];

  // 7. Convert to Normalized Points
  NSMutableArray<NSValue *> *resultPoints = [NSMutableArray array];
  const std::vector<cv::Point> &bestContour = contours[maxIdx];

  // Approx poly to smooth it a bit?
  // Balloons are smooth.
  std::vector<cv::Point> approxCurve;
  cv::approxPolyDP(bestContour, approxCurve, 2.0, true);

  for (const auto &pt : approxCurve) {
    CGPoint p = CGPointMake((CGFloat)pt.x / w, (CGFloat)pt.y / h);
    [resultPoints addObject:[NSValue valueWithCGPoint:p]];
  }

  return resultPoints;
}

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
