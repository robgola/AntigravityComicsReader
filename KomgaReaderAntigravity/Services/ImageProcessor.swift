import SwiftUI
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

class ImageProcessor {
    static let shared = ImageProcessor()
    private let context = CIContext()
    
    private init() {}
    
    // MARK: - Image Enhancement (Pre-OCR)
    /// Enhances image for better OCR accuracy using OpenCV
    func enhanceForOCR(image: UIImage) -> UIImage {
        return OpenCVWrapper.enhanceImage(forOCR: image)
    }
}
