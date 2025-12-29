import SwiftUI
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

struct DetectedBubble: Identifiable {
    let id = UUID()
    let path: Path
    let boundingBox: CGRect // Normalized (0-1)
    let originalRects: [CGRect] // For debugging or fallback
}

class BubbleDetector {
    static let shared = BubbleDetector()
    
    private init() {}
    
    func detectBubbles(in image: UIImage, observations: [VNRecognizedTextObservation], extraSeeds: [CGPoint] = []) async -> [DetectedBubble] {
        return await Task.detached(priority: .userInitiated) {
            // 1. Downsample for speed (width ~500px)
            let targetWidth: CGFloat = 500
            let scale = targetWidth / image.size.width
            let targetHeight = image.size.height * scale
            let targetSize = CGSize(width: targetWidth, height: targetHeight)
            
            guard let resizedImage = self.resizeImage(image: image, targetSize: targetSize) else { return [] }
            
            // 2. Get Raw Data (No CoreImage Preprocessing - Keep Edges Sharp!)
            guard let cgImage = resizedImage.cgImage,
                  let dataProvider = cgImage.dataProvider,
                  let data = dataProvider.data,
                  let originalPtr = CFDataGetBytePtr(data) else { return [] }
            
            let width = cgImage.width
            let height = cgImage.height
            let bytesPerRow = cgImage.bytesPerRow
            let bytesPerPixel = 4 // RGBA
            
            // 3. CREATE TEXT MASK (Super-Conductors)
            // Mark all text regions. These act as "bridges" for the flood fill.
            var isTextRegion = Array(repeating: false, count: width * height)
            var seeds: [(x: Int, y: Int, r: Int, g: Int, b: Int)] = []
            
            // Generate Mask Rects (Observations ONLY - No Bridges)
            // Reverting to simple observation-based masking to prevent leaks.
            
            for obs in observations {
                let visionBox = obs.boundingBox
                let normRect = CGRect(
                    x: visionBox.minX,
                    y: 1.0 - visionBox.maxY,
                    width: visionBox.width,
                    height: visionBox.height
                )
                
                let rect = CGRect(
                    x: normRect.minX * CGFloat(width),
                    y: normRect.minY * CGFloat(height),
                    width: normRect.width * CGFloat(width),
                    height: normRect.height * CGFloat(height)
                )
                
                // Inset the text rect slightly to avoid touching the bubble border
                // Standard safety inset.
                let safeRect = rect.insetBy(dx: 2, dy: 2)
                
                let startX = max(0, Int(safeRect.minX))
                let endX = min(width, Int(safeRect.maxX))
                let startY = max(0, Int(safeRect.minY))
                let endY = min(height, Int(safeRect.maxY))
                
                guard startX < endX && startY < endY else { continue }
                
                // Mark region
                for y in startY..<endY {
                    for x in startX..<endX {
                        isTextRegion[y * width + x] = true
                    }
                }
                
                // Calculate Target Color from Perimeter (Smart Sampling)
                // Only do this for the ORIGINAL observations, not bridges (bridges might be empty space)
                // But we are iterating maskRects now.
                // We need seeds. Let's generate seeds only for the original observations loop?
                // Or just generate seeds for everything? If bridge is empty space, color will be paper color. That's fine.
                
                var rSum = 0, gSum = 0, bSum = 0, count = 0
                
                // ... (Sampling Logic) ...
                // Use original rect for sampling
                
                // Top & Bottom edges
                let sampleStartX = max(0, Int(rect.minX))
                let sampleEndX = min(width, Int(rect.maxX))
                let sampleStartY = max(0, Int(rect.minY))
                let sampleEndY = min(height, Int(rect.maxY))
                
                let edgesY = [max(0, sampleStartY - 2), min(height - 1, sampleEndY + 2)]
                for y in edgesY {
                    for x in sampleStartX...sampleEndX {
                        if x >= 0 && x < width {
                            let off = y * bytesPerRow + x * bytesPerPixel
                            let r = Int(originalPtr[off])
                            let g = Int(originalPtr[off + 1])
                            let b = Int(originalPtr[off + 2])
                            
                            if (r + g + b) > 400 { // Ignore dark pixels
                                rSum += r
                                gSum += g
                                bSum += b
                                count += 1
                            }
                        }
                    }
                }
                
                // Left & Right edges
                let edgesX = [max(0, sampleStartX - 2), min(width - 1, sampleEndX + 2)]
                for x in edgesX {
                    for y in sampleStartY...sampleEndY {
                        if y >= 0 && y < height {
                            let off = y * bytesPerRow + x * bytesPerPixel
                            let r = Int(originalPtr[off])
                            let g = Int(originalPtr[off + 1])
                            let b = Int(originalPtr[off + 2])
                            
                            if (r + g + b) > 400 {
                                rSum += r
                                gSum += g
                                bSum += b
                                count += 1
                            }
                        }
                    }
                }
                
                var bgR = 255, bgG = 255, bgB = 255
                if count > 0 {
                    bgR = rSum / count
                    bgG = gSum / count
                    bgB = bSum / count
                }
                
                // --- BACKGROUND COLOR VALIDATION ---
                // Filter out text that is likely NOT in a balloon (e.g. logos, badges, titles on art)
                // Balloon backgrounds are typically:
                // 1. White / Light Grey (Standard)
                // 2. Light Yellow (Old comics)
                // 3. Light Blue (Thoughts)
                // They are rarely Dark, Vivid Red, Vivid Green, etc.
                
                // 1. Check Brightness (0-255)
                let brightness = (bgR + bgG + bgB) / 3
                let isDark = brightness < 150 // Lowered from 200 to 150 to detect vintage/beige paper
                
                // 2. Check Saturation (Approximate)
                // |R-G| + |R-B| + |G-B| is a rough proxy for saturation
                let saturation = abs(bgR - bgG) + abs(bgR - bgB) + abs(bgG - bgB)
                let isVivid = saturation > 60 // Allow some tint (yellow/blue) but not strong colors
                
                // Exception: Allow Yellowish (High R, High G, Low B) -> Old paper
                let isYellowish = (bgR > 200 && bgG > 200 && bgB < 200)
                
                // Exception: Allow Light Blueish (High B, High G/R) -> Thought bubbles
                let isBlueish = (bgB > 200 && bgG > 180 && bgR > 180)
                
                if isDark && !isYellowish && !isBlueish {
                    // print("Skipping dark background text: RGB(\(bgR), \(bgG), \(bgB))")
                    continue
                }
                
                if isVivid && !isYellowish && !isBlueish {
                    // print("Skipping vivid background text: RGB(\(bgR), \(bgG), \(bgB))")
                    continue
                }
                // -----------------------------------
                
                let centerX = (startX + endX) / 2
                let centerY = (startY + endY) / 2
                seeds.append((centerX, centerY, bgR, bgG, bgB))
            }
            
            // 3b. INJECT HYBRID ANCHORS (Gemini Center Points) with SMART SAMPLING
            // These are normalized coordinates (0-1) from Gemini's "center_point"
            for point in extraSeeds {
                // Denormalize to resized image coordinates
                let px = Int(point.x * CGFloat(width))
                let py = Int(point.y * CGFloat(height))
                
                guard px >= 0 && px < width && py >= 0 && py < height else { continue }
                
                // SMART SAMPLING:
                // If the exact center is text (Dark), we must find the background color nearby.
                // We spiral out up to 20 pixels to find a "Light" pixel.
                
                var bestColor: (r: Int, g: Int, b: Int)? = nil
                
                // 1. Try exact center first
                if let (r, g, b) = self.sampleColor(at: px, y: py, width: width, height: height, bytesPerRow: bytesPerRow, ptr: originalPtr) {
                    let brightness = (r + g + b) / 3
                    if brightness > 150 {
                        bestColor = (r, g, b) // Found light background immediately
                    }
                }
                
                // 2. If not found or too dark, spiral search
                if bestColor == nil {
                    let searchRadius = 20
                    searchLoop: for r in stride(from: 2, through: searchRadius, by: 2) {
                        for dy in -r...r {
                            for dx in -r...r {
                                // Only check the perimeter of the box to save time
                                if abs(dx) != r && abs(dy) != r { continue }
                                
                                let sx = px + dx
                                let sy = py + dy
                                
                                if let (r, g, b) = self.sampleColor(at: sx, y: sy, width: width, height: height, bytesPerRow: bytesPerRow, ptr: originalPtr) {
                                    let brightness = (r + g + b) / 3
                                    if brightness > 150 {
                                        bestColor = (r, g, b)
                                        // Update seed position to this clear spot to ensure flood fill starts well
                                        // actually, keep original seed but use this TARGET color?
                                        // Better to start flood fill from the clean spot.
                                        // But we add it as a new seed.
                                        seeds.append((sx, sy, r, g, b))
                                        break searchLoop // Found a good spot!
                                    }
                                }
                            }
                        }
                    }
                } else if let c = bestColor {
                     seeds.append((px, py, c.r, c.g, c.b))
                }
            }
            
            // 4. FLOOD FILL
            var visited = Array(repeating: false, count: width * height)
            var detectedBubbles: [DetectedBubble] = []
            
            for seed in seeds {
                let seedIdx = seed.y * width + seed.x
                if seedIdx < 0 || seedIdx >= visited.count || visited[seedIdx] { continue }
                
                var pixels: Set<Int> = []
                var queue: [Int] = [seedIdx]
                visited[seedIdx] = true
                pixels.insert(seedIdx)
                
                let targetR = seed.r
                let targetG = seed.g
                let targetB = seed.b
                
                // Restore Tolerance
                let tolerance = 40
                let edgeThreshold = 40
                
                while !queue.isEmpty {
                    let idx = queue.removeFirst()
                    let cx = idx % width
                    let cy = idx / width
                    
                    // Get current pixel color
                    // VIRTUALIZATION: If current pixel is text ink, treat as target color
                    // This allows us to "calculate local diff" correctly from a virtualized pixel
                    var cR = 0, cG = 0, cB = 0
                    
                    let cOffset = cy * bytesPerRow + cx * bytesPerPixel
                    let rawCR = Int(originalPtr[cOffset])
                    let rawCG = Int(originalPtr[cOffset + 1])
                    let rawCB = Int(originalPtr[cOffset + 2])
                    
                    if isTextRegion[idx] && (rawCR + rawCG + rawCB) < 300 {
                        cR = targetR; cG = targetG; cB = targetB
                    } else {
                        cR = rawCR; cG = rawCG; cB = rawCB
                    }
                    
                    let neighbors = [
                        (cx - 1, cy), (cx + 1, cy),
                        (cx, cy - 1), (cx, cy + 1)
                    ]
                    
                    for (nx, ny) in neighbors {
                        if nx >= 0 && nx < width && ny >= 0 && ny < height {
                            let nIdx = ny * width + nx
                            if !visited[nIdx] {
                                let nOffset = ny * bytesPerRow + nx * bytesPerPixel
                                let rawR = Int(originalPtr[nOffset])
                                let rawG = Int(originalPtr[nOffset + 1])
                                let rawB = Int(originalPtr[nOffset + 2])
                                
                                // VIRTUALIZATION:
                                // If neighbor is inside text region AND is dark (ink),
                                // pretend it is the target background color.
                                var r = rawR, g = rawG, b = rawB
                                if isTextRegion[nIdx] && (rawR + rawG + rawB) < 300 {
                                    r = targetR
                                    g = targetG
                                    b = targetB
                                }
                                
                                // 1. Check for Black Border
                                // Use RAW color for border check?
                                // If we virtualize, we hide the border.
                                // But we inset the text region, so the border should be OUTSIDE the mask.
                                // So if we hit a border, isTextRegion should be false, so we use raw color.
                                // Correct.
                                let brightness = (rawR + rawG + rawB) / 3
                                let isBorder = brightness < 60 // Standard threshold
                                
                                // 2. Check Color Similarity
                                let diff = abs(r - targetR) + abs(g - targetG) + abs(b - targetB)
                                let isSimilar = diff < tolerance * 3
                                
                                // 3. Check Local Edge (Restored!)
                                let diffLocal = abs(r - cR) + abs(g - cG) + abs(b - cB)
                                let isSoftEdge = diffLocal < edgeThreshold * 3
                                
                                if !isBorder && isSimilar && isSoftEdge {
                                    visited[nIdx] = true
                                    pixels.insert(nIdx)
                                    queue.append(nIdx)
                                }
                            }
                        }
                    }
                }
                
                // Create Bubble
                if pixels.count > 50 {
                    // Calculate Bounding Box
                    var minX = width, maxX = 0, minY = height, maxY = 0
                    for idx in pixels {
                        let x = idx % width
                        let y = idx / width
                        if x < minX { minX = x }
                        if x > maxX { maxX = x }
                        if y < minY { minY = y }
                        if y > maxY { maxY = y }
                    }
                    
                    let w = maxX - minX + 1
                    let h = maxY - minY + 1
                    
                    let path = self.createPathFromPixels(pixels: pixels, width: width, height: height)
                    let normalizedPath = self.normalizePath(path, width: CGFloat(width), height: CGFloat(height))
                    let normalizedRect = CGRect(
                        x: CGFloat(minX) / CGFloat(width),
                        y: CGFloat(minY) / CGFloat(height),
                        width: CGFloat(w) / CGFloat(width),
                        height: CGFloat(h) / CGFloat(height)
                    )
                    
                    detectedBubbles.append(DetectedBubble(path: normalizedPath, boundingBox: normalizedRect, originalRects: []))
                }
            }
            
            // 5. MERGE OVERLAPPING/CLOSE BUBBLES
            return self.mergeBubbles(detectedBubbles)
        }.value
    }
    
    nonisolated private func mergeBubbles(_ bubbles: [DetectedBubble]) -> [DetectedBubble] {
        // User feedback: distinct overlapping bubbles were being merged.
        // The Flood Fill algorithm naturally separates bubbles separated by black lines.
        // The previous "intersect/proximity" merging was undoing this precision.
        // We will now ONLY merge if one bubble is essentially fully inside another (duplicate detection).
        
        var merged = bubbles
        var changed = true
        
        while changed {
            changed = false
            var i = 0
            while i < merged.count {
                var j = i + 1
                while j < merged.count {
                    let b1 = merged[i]
                    let b2 = merged[j]
                    
                    // Check containment only (to remove duplicates/ghosts)
                    let r1 = b1.boundingBox
                    let r2 = b2.boundingBox
                    
                    let intersection = r1.intersection(r2)
                    let areaInt = intersection.width * intersection.height
                    let area1 = r1.width * r1.height
                    let area2 = r2.width * r2.height
                    
                    var shouldMerge = false
                    
                    // If one is > 90% inside the other, merge (likely same bubble detected twice)
                    if areaInt > 0.9 * min(area1, area2) {
                        shouldMerge = true
                    }
                    
                    if shouldMerge {
                        // Merge!
                        var newPath = b1.path
                        newPath.addPath(b2.path)
                        let newRect = b1.boundingBox.union(b2.boundingBox)
                        
                        let newBubble = DetectedBubble(path: newPath, boundingBox: newRect, originalRects: b1.originalRects + b2.originalRects)
                        
                        merged[i] = newBubble
                        merged.remove(at: j)
                        changed = true
                    } else {
                        j += 1
                    }
                }
                i += 1
            }
        }
        return merged
    }
    
    nonisolated private func resizeImage(image: UIImage, targetSize: CGSize) -> UIImage? {
        // Use UIGraphicsImageRenderer to respect UIImage orientation automatically
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0 // Keep 1:1 scale for pixel processing
        format.opaque = false
        
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
    
    nonisolated private func createPathFromPixels(pixels: Set<Int>, width: Int, height: Int) -> Path {
        // Strategy: "Row Filling"
        // Robust and handles holes perfectly.
        
        var path = Path()
        
        // Group by Y
        var rows: [Int: [Int]] = [:]
        for idx in pixels {
            let y = idx / width
            let x = idx % width
            if rows[y] == nil { rows[y] = [] }
            rows[y]?.append(x)
        }
        
        for (y, xs) in rows {
            guard let minX = xs.min(), let maxX = xs.max() else { continue }
            
            // Create one rect for the whole span
            let rect = CGRect(x: minX, y: y, width: maxX - minX + 1, height: 1)
            path.addRect(rect)
        }
        
        return path
    }
    
    nonisolated private func normalizePath(_ path: Path, width: CGFloat, height: CGFloat) -> Path {
        let transform = CGAffineTransform(scaleX: 1.0 / width, y: 1.0 / height)
        return path.applying(transform)
    }
    
    nonisolated private func sampleColor(at x: Int, y: Int, width: Int, height: Int, bytesPerRow: Int, ptr: UnsafePointer<UInt8>) -> (r: Int, g: Int, b: Int)? {
        // Robust sampling: Check 5x5 area around point to avoid noise
        let range = -2...2
        var rSum = 0, gSum = 0, bSum = 0, count = 0
        
        for dy in range {
            for dx in range {
                let px = x + dx
                let py = y + dy
                
                if px >= 0 && px < width && py >= 0 && py < height {
                    let off = py * bytesPerRow + px * 4
                    let r = Int(ptr[off])
                    let g = Int(ptr[off+1])
                    let b = Int(ptr[off+2])
                    
                    // Filter out very dark pixels (ink)
                    // If brightness < 50, it's likely text/ink, not background
                    // UNLESS the background ITSELF is dark (detected below)
                    // For now, simple averager
                    rSum += r
                    gSum += g
                    bSum += b
                    count += 1
                }
            }
        }
        
        if count == 0 { return nil }
        
        let bgR = rSum / count
        let bgG = gSum / count
        let bgB = bSum / count
        
        // --- VALIDATION logic reused from original code ---
        // 1. Check Brightness (0-255)
        let brightness = (bgR + bgG + bgB) / 3
        let isDark = brightness < 50 // Severely lowered threshold (was 200). Only skip absolute void.
        
        // 2. Check Saturation
        // let saturation = abs(bgR - bgG) + abs(bgR - bgB) + abs(bgG - bgB)
        // let isVivid = saturation > 150
        
        // Exception: Allow Yellowish
        let isYellowish = (bgR > 200 && bgG > 200 && bgB < 200)
        
        // Exception: Allow Light Blueish
        let isBlueish = (bgB > 200 && bgG > 180 && bgR > 180)
        
        if isDark && !isYellowish && !isBlueish {
             if brightness < 30 { return nil }
        }
        
        return (bgR, bgG, bgB)
    }
}
