import Foundation
import UIKit
import SwiftUI

/// Orchestrates the v6.0 Pipeline: Detection -> Segmentation -> Translation
actor BalloonPipeline {
    static let shared = BalloonPipeline()
    
    private init() {}
    
    /// Main entry point: Process a full comic page (Hybrid v6.1 Strategy)
    func processPage(image: UIImage) async throws -> [TranslatedBalloon] {
        print("🚀 Pipeline v6.1: Starting Hybrid Processing...")
        let startTime = Date()
        
        // 1. Launch Parallel Requests: Structure (YOLO) & Semantics (Gemini)
        async let yoloTask = BalloonDetector.shared.detect(in: image)
        async let geminiTask = GeminiService.shared.fetchSemanticData(image: image)
        
        // 2. Await Results
        let (yoloDetections, geminiData) = try await (yoloTask, geminiTask)
        
        print("   - Step 1 (Parallel): Found \(yoloDetections.count) YOLO detections and \(geminiData.balloons.count) Gemini captions.")
        
        var mergedBalloons: [TranslatedBalloon] = []
        
        // 3. Merge Logic (Multi-Stage)
        var matchedYoloIndices = Set<Int>()
        var unmatchedGeminiBalloons: [(index: Int, rect: CGRect)] = []
        
        // Stage A: Strict IoU Matching
        for (gIndex, var gBalloon) in geminiData.balloons.enumerated() {
            guard gBalloon.should_translate else { continue }
            
            let gBox = gBalloon.box2D
            let geminiRect = CGRect(
                x: CGFloat(gBox[1]) / 1000.0,
                y: CGFloat(gBox[0]) / 1000.0,
                width: CGFloat(gBox[3] - gBox[1]) / 1000.0,
                height: CGFloat(gBox[2] - gBox[0]) / 1000.0
            )
            
            var bestMatchIndex: Int? = nil
            var bestIoU: CGFloat = 0.0
            
            for (yIndex, yolo) in yoloDetections.enumerated() {
                if matchedYoloIndices.contains(yIndex) { continue }
                
                let intersection = geminiRect.intersection(yolo.normalizedRect)
                let union = geminiRect.union(yolo.normalizedRect)
                let uArea = union.width * union.height
                if uArea > 0 {
                    let iou = (intersection.width * intersection.height) / uArea
                    if iou > 0.1 && iou > bestIoU {
                        bestIoU = iou
                        bestMatchIndex = yIndex
                    }
                }
            }
            
            if let idx = bestMatchIndex {
                matchedYoloIndices.insert(idx)
                let match = yoloDetections[idx]
                let r = match.normalizedRect
                
                // Update with Precise YOLO Box
                let updatedBalloon = TranslatedBalloon(
                    originalText: gBalloon.originalText,
                    translatedText: gBalloon.translatedText,
                    should_translate: true,
                    shape: gBalloon.shape,
                    box2D: [
                        Int(r.minY * 1000), Int(r.minX * 1000), Int(r.maxY * 1000), Int(r.maxX * 1000)
                    ],
                    centerPoint: nil
                )
                print("   - [IoU Match] Linked Gemini text '\(gBalloon.originalText.prefix(10))...' with YOLO box (IoU: \(String(format: "%.2f", bestIoU)))")
                mergedBalloons.append(updatedBalloon)
            } else {
                // No overlapping match found, save for Stage B
                unmatchedGeminiBalloons.append((gIndex, geminiRect))
            }
        }
        
        // Stage B: Distance-Based Fallback
        // Iterate through remaining Gemini balloons and try to match closest remaining YOLO box
        for (gIndex, gRect) in unmatchedGeminiBalloons {
            let gBalloon = geminiData.balloons[gIndex]
            let gCenter = CGPoint(x: gRect.midX, y: gRect.midY)
            
            var closestYoloIndex: Int? = nil
            var minDistance: CGFloat = CGFloat.greatestFiniteMagnitude
            
            for (yIndex, yolo) in yoloDetections.enumerated() {
                if matchedYoloIndices.contains(yIndex) { continue }
                
                let yRect = yolo.normalizedRect
                let yCenter = CGPoint(x: yRect.midX, y: yRect.midY)
                let dist = hypot(gCenter.x - yCenter.x, gCenter.y - yCenter.y)
                
                if dist < minDistance {
                    minDistance = dist
                    closestYoloIndex = yIndex
                }
            }
            
            if let idx = closestYoloIndex {
                // Heuristic: Only match if distance is reasonable (e.g. < 0.3 of page width)
                // to avoid matching a top-left text with a bottom-right box.
                if minDistance < 0.3 {
                    matchedYoloIndices.insert(idx)
                    let match = yoloDetections[idx]
                    let r = match.normalizedRect
                    
                    let updatedBalloon = TranslatedBalloon(
                        originalText: gBalloon.originalText,
                        translatedText: gBalloon.translatedText,
                        should_translate: true,
                        shape: gBalloon.shape,
                        box2D: [
                            Int(r.minY * 1000), Int(r.minX * 1000), Int(r.maxY * 1000), Int(r.maxX * 1000)
                        ],
                        centerPoint: nil
                    )
                    print("   - [Dist Match] Fallback link '\(gBalloon.originalText.prefix(10))...' with closest YOLO box (Dist: \(String(format: "%.2f", minDistance)))")
                    mergedBalloons.append(updatedBalloon)
                } else {
                     print("   - [No Match] Gemini text '\(gBalloon.originalText.prefix(10))...' too far from any free YOLO box. Using approx box.")
                     mergedBalloons.append(gBalloon)
                }
            } else {
                 print("   - [No Match] No free YOLO boxes left for '\(gBalloon.originalText.prefix(10))...'. Using approx box.")
                 mergedBalloons.append(gBalloon)
            }
        }
        
        // 5. Refinement (GrabCut) - Parallel Execution
        // Now we refine the Merged Balloons
        var refinedBalloons: [TranslatedBalloon] = []
        
        await withTaskGroup(of: TranslatedBalloon?.self) { group in
            for balloon in mergedBalloons {
                group.addTask {
                    return await self.refineBalloon(balloon, originalImage: image)
                }
            }
            
            for await result in group {
                if let vb = result {
                    refinedBalloons.append(vb)
                }
            }
        }
        
        print("✅ Pipeline v6.1: Completed in \(Date().timeIntervalSince(startTime))s. (\(refinedBalloons.count) processed)")
        return refinedBalloons
    }
    
    /// Refines a single Pre-Calculated Balloon with GrabCut
    private func refineBalloon(_ balloon: TranslatedBalloon, originalImage: UIImage) async -> TranslatedBalloon {
        var refined = balloon
        let rect = balloon.boundingBox // 0-1 Normalized
        
        // GrabCut: Use strict YOLO box as requested by user.
        // Reverted inflation logic.
        
        let contour = OpenCVWrapper.refinedBalloonContour(originalImage, textRect: rect)
        
        // Flatten [NSValue] (CGPoint) to Path
        // GrabCut returns [NSValue<CGPoint>]
        let points = contour
        if !points.isEmpty {
            let cgPoints = points.map { $0.cgPointValue }
            // print("   - [GrabCut] Success: \(cgPoints.count) points for rect \(rect)")
            refined.localPath = Path { p in
                p.addLines(cgPoints)
                p.closeSubpath()
            }
            
            // Optional: Sample Background Color from center of refined path?
            // For now, white is standard for comics.
            refined.backgroundColor = .white
        } else {
            print("   - [GrabCut] FAILED/Skipped for rect \(rect). Using standard shape.")
        }
        
        return refined
    }
    
    // Legacy processSingleBalloon removed as it's no longer used in v6.1 logic
}
