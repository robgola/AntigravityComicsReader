import SwiftUI
import Vision
import ImageIO

extension CGImagePropertyOrientation {
    init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
            case .up: self = .up
            case .upMirrored: self = .upMirrored
            case .down: self = .down
            case .downMirrored: self = .downMirrored
            case .left: self = .left
            case .leftMirrored: self = .leftMirrored
            case .right: self = .right
            case .rightMirrored: self = .rightMirrored
            @unknown default: self = .up
        }
    }
}

class VisionService {
    static let shared = VisionService()
    
    private init() {}
    
    struct TextResult {
        let text: String
        let confidence: Float
        let boundingBox: CGRect // In image coordinates
    }
    
    /// Extracts text from a specific balloon region
    func extractText(from image: UIImage, in balloonRect: CGRect) async -> TextResult? {
        // 1. Crop with Padding
        // Add 15% padding to avoid cutting off edge words (increased from 10%)
        let padding: CGFloat = 0.15
        let paddedRect = balloonRect.insetBy(dx: -balloonRect.width * padding, dy: -balloonRect.height * padding)
        
        // Ensure we don't go out of bounds (0-1 normalized)
        let safeRect = paddedRect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        
        guard let croppedImage = cropImage(image, to: safeRect) else { return nil }
        
        // 2. Preprocess with OpenCV for better edge detection
        let enhancedImage = ImageProcessor.shared.enhanceForOCR(image: croppedImage)
        
        // 3. OCR
        return await performOCR(on: enhancedImage, originalRect: balloonRect)
    }
    
    private func cropImage(_ image: UIImage, to rect: CGRect) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        
        let cropRect = CGRect(
            x: rect.minX * width,
            y: rect.minY * height,
            width: rect.width * width,
            height: rect.height * height
        )
        
        guard let croppedCG = cgImage.cropping(to: cropRect) else { return nil }
        return UIImage(cgImage: croppedCG)
    }
    
    /// Normalizes the image orientation by drawing it into a new context.
    /// This ensures the CGImage has the same orientation as the displayed UIImage.
    func normalizeImage(_ image: UIImage) -> UIImage? {
        if image.imageOrientation == .up { return image }
        
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return normalizedImage
    }
    
    private func performOCR(on image: UIImage, originalRect: CGRect) async -> TextResult? {
        guard let cgImage = image.cgImage else { return nil }
        
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard let observations = request.results as? [VNRecognizedTextObservation], error == nil else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Combine text
                let fullText = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
                
                // Calculate average confidence
                let totalConfidence = observations.reduce(0.0) { $0 + ($1.topCandidates(1).first?.confidence ?? 0) }
                let avgConfidence = observations.isEmpty ? 0 : totalConfidence / Float(observations.count)
                
                if fullText.isEmpty {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: TextResult(
                        text: fullText,
                        confidence: avgConfidence,
                        boundingBox: originalRect
                    ))
                }
            }
            
            // Use Revision 3 (iOS 16+ "Live Text" engine)
            if #available(iOS 16.0, *) {
                request.revision = VNRecognizeTextRequestRevision3
            } else {
                request.revision = VNRecognizeTextRequestRevision2
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            
            // Maximize recognition for comics
            request.recognitionLanguages = ["en-US"] // Explicit English
            request.customWords = [] // Could add common comic words if needed
            request.minimumTextHeight = 0.01 // Allow smaller text (sound effects, whispers)
            
            // Pass orientation to Vision
            let orientation = CGImagePropertyOrientation(image.imageOrientation)
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            do {
                try handler.perform([request])
            } catch {
                print("OCR Error: \(error)")
                continuation.resume(returning: nil)
            }
        }
    }
}
