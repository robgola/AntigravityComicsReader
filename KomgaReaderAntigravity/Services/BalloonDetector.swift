import Foundation
import UIKit
import Vision
import CoreML

/// Represents a raw detection from the Object Detector (YOLO)
struct DetectedBalloon {
    let id: UUID = UUID()
    let normalizedRect: CGRect // 0.0-1.0
    let confidence: Float
    // We might add 'classIndex' if we detect multiple types (Speech, Thought, box)
}

/// Handles local object detection using Core ML (YOLOv8)
enum BalloonDetectorError: Error {
    case modelNotFound
    case imageProcessingFailed
    case detectionFailed(Error)
}

actor BalloonDetector {
    static let shared = BalloonDetector()
    
    private var visionModel: VNCoreMLModel?
    private var isModelLoaded = false
    
    // Config
    private let modelName = "comic-speech-bubble-detector" // Exact name of the .mlpackage
    private let confidenceThreshold: Float = 0.35 // Tunable
    
    private init() {
        // Lazy load on first use to speed up app launch
    }
    
    /// Loads the compiled Core ML model using the Auto-Generated Class
    private func loadModel() throws {
        guard !isModelLoaded else { return }
        
        do {
            // Xcode generates a class named `comic_speech_bubble_detector` (replacing hyphens with underscores)
            // We instantiate it directly.
            let modelConfig = MLModelConfiguration()
            let generatedModel = try comic_speech_bubble_detector(configuration: modelConfig)
            
            self.visionModel = try VNCoreMLModel(for: generatedModel.model)
            self.isModelLoaded = true
            print("✅ BalloonDetector: Loaded comic_speech_bubble_detector (Auto-Generated Class)")
        } catch {
            print("❌ BalloonDetector: Failed to load model: \(error)")
            throw error
        }
    }
    
    /// Detects balloons in the provided image using Vision + Core ML
    func detect(in image: UIImage) async throws -> [DetectedBalloon] {
        if !isModelLoaded {
            try loadModel()
        }
        
        guard let model = visionModel else {
            throw BalloonDetectorError.modelNotFound
        }
        
        guard let cgImage = image.cgImage else {
            throw BalloonDetectorError.imageProcessingFailed
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNCoreMLRequest(model: model) { request, error in
                if let error = error {
                    continuation.resume(throwing: BalloonDetectorError.detectionFailed(error))
                    return
                }
                
                guard let results = request.results as? [VNRecognizedObjectObservation] else {
                    continuation.resume(returning: [])
                    return
                }
                
                // Filter for 'text_bubble' (and maybe 'text_free'?)
                // The screenshot shows 80 classes, but specifically `text_bubble` and `text_free`.
                // Let's accept both for now as "balloons".
                
                let balloons = results
                    .filter { observation in
                         observation.confidence > self.confidenceThreshold &&
                         (observation.labels.first?.identifier == "text_bubble" ||
                          observation.labels.first?.identifier == "text_free")
                    }
                    .map { observation in
                        // VNRecognizedObjectObservation.boundingBox is already normalized (0-1),
                        // but Origin is bottom-left for Vision. 
                        // However, VNCoreMLRequest handles orientation if configured?
                        // Actually, VNCoreMLRequest usually returns normalized coords with 
                        // Origin BOTTOM-LEFT (standard CoreGraphics/Vision).
                        // UIKit uses Top-Left. We might need to flip Y.
                        // Let's verify standard YOLO/Vision behavior.
                        // Usually Vision rects are Bottom-Left origin.
                        // We need to convert to UIKit (Top-Left origin).
                        
                        let visionRect = observation.boundingBox
                        // Flip Y for UIKit
                        let uiRect = CGRect(
                            x: visionRect.origin.x,
                            y: 1.0 - visionRect.origin.y - visionRect.size.height,
                            width: visionRect.size.width,
                            height: visionRect.size.height
                        )
                        
                        return DetectedBalloon(
                            normalizedRect: uiRect,
                            confidence: observation.confidence
                        )
                    }
                
                continuation.resume(returning: balloons)
            }
            
            // Standard Vision config
            request.imageCropAndScaleOption = .scaleFit // Use scaleFit to preserve aspect ratio (letterbox)
            
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: BalloonDetectorError.detectionFailed(error))
            }
        }
    }
}
