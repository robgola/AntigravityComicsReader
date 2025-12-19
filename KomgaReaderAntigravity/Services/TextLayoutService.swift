import UIKit
import CoreText

struct LaidOutLine {
    let text: String
    let position: CGPoint // Relative to path bounding box origin
    let width: CGFloat
    let ctLine: CTLine
}

struct LaidOutText {
    let lines: [LaidOutLine]
    let totalHeight: CGFloat
    let fontSize: CGFloat
}

class TextLayoutService {
    static let shared = TextLayoutService()
    
    // Main Entry Point
    func layoutText(_ text: String, in path: CGPath, fontName: String, minSize: CGFloat = 10, maxSize: CGFloat = 42) -> LaidOutText? {
        let boundingBox = path.boundingBox
        
        // Binary Search for optimal Font Size
        var low = minSize
        var high = maxSize
        var bestLayout: LaidOutText? = nil
        
        // We favor larger fonts, so we check "is valid" from high to low essentially
        // Standard binary search to find MAX size
        
        while low <= high {
            let mid = floor((low + high) / 2)
            if let layout = tryLayout(text, in: path, boundingBox: boundingBox, fontSize: mid, fontName: fontName) {
                bestLayout = layout
                low = mid + 1 // See if we can go bigger
            } else {
                high = mid - 1 // Too big, go smaller
            }
        }
        
        return bestLayout
    }
    
    // Core Layout Algorithm (Scanline)
    private func tryLayout(_ text: String, in path: CGPath, boundingBox: CGRect, fontSize: CGFloat, fontName: String) -> LaidOutText? {
        // 1. Setup Font & Attributes
        guard let font = UIFont(name: fontName, size: fontSize) else {
            print("⚠️ Font '\(fontName)' not found! Using condensed system font.")
            // Fallback to condensed font for better fitting
            let systemFont = UIFont(name: "HelveticaNeue-Medium", size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)
            return tryLayoutWithFont(text, in: path, boundingBox: boundingBox, font: systemFont)
        }
        return tryLayoutWithFont(text, in: path, boundingBox: boundingBox, font: font)
    }
    
    private func tryLayoutWithFont(_ text: String, in path: CGPath, boundingBox: CGRect, font: UIFont) -> LaidOutText? {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let _ = NSAttributedString(string: text, attributes: attributes)
        
        // 2. Tokenize words (simple space splitting, preserving newlines could be added later)
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        if words.isEmpty { return nil }
        
        var currentWordIndex = 0
        var lines: [LaidOutLine] = []
        
        // 3. Scanline Setup
        // We start from the top of the bounding box and move down by lineHeight
        // We assume centered vertical alignment implicitly by trying to pack from top?
        // Actually, speech bubbles usually align vertically center.
        // To achieve ONLY fitting check, packing from top is fine. 
        // Logic: Try to write lines. If we run out of space before words are done, fail.
        
        let fontSize = font.pointSize
        let lineHeight = fontSize * 1.1 // 10% Leading
        let ascent = font.ascender
        let descent = font.descender
        let _ = font.capHeight
        
        // Heuristic: Start writing at minY + padding? 
        // Or better: Scan the shape to find the first "usable" line.
        
        var currentY = boundingBox.minY + lineHeight // Start a bit inside
        let maxY = boundingBox.maxY - (lineHeight * 0.5)
        
        while currentY < maxY && currentWordIndex < words.count {
            // 4. Calculate Available Width at this Y
            // We sample horizontal segments.
            // For a convex bubble, just finding leftmost and rightmost points is enough.
            // We'll scan with a coarse step (e.g. 4 points)
            
            let centerLineY = currentY - (lineHeight * 0.3) // Approximate visual center of text
            let scanStep: CGFloat = 4.0
            
            var minX: CGFloat = .greatestFiniteMagnitude
            var maxX: CGFloat = -.greatestFiniteMagnitude
            var found = false
            
            // Scan X
            var x = boundingBox.minX
            while x <= boundingBox.maxX {
                if path.contains(CGPoint(x: x, y: centerLineY)) {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    found = true
                }
                x += scanStep
            }
            
            if !found || (maxX - minX) < (fontSize * 2) {
                // Determine if this line is unusable (too narrow or empty)
                currentY += lineHeight
                continue
            }
            
            // Apply padding (increased to prevent overflow)
            let padding: CGFloat = 8.0
            let availableWidth = (maxX - minX) - (padding * 2)
            if availableWidth <= 0 {
                currentY += lineHeight
                continue
            }
            
            // 5. Fit Words into this Line
            var currentLineWords: [String] = []

            
            while currentWordIndex < words.count {
                let word = words[currentWordIndex]
                let spacer = currentLineWords.isEmpty ? "" : " "
                let testLineString = currentLineWords.joined(separator: " ") + spacer + word
                
                // Measure
                let testAttr = NSAttributedString(string: testLineString, attributes: attributes)
                let testLine = CTLineCreateWithAttributedString(testAttr)
                let width = CGFloat(CTLineGetTypographicBounds(testLine, nil, nil, nil))
                
                if width <= availableWidth {
                    // Fits
                    currentLineWords.append(word)
                    // currentLineWidth = width // Unused

                    currentWordIndex += 1
                } else {
                    // Overflow
                    break
                }
            }
            
            // If we couldn't fit even ONE word in this line, but the line was "usable" geometrically...
            // It means the word is wider than the bubble at this point (or bubble is narrow).
            // If we are at the start of a line and fail to fit, we must skip this line (it's too narrow for the word).
            if currentLineWords.isEmpty {
                currentY += lineHeight
                continue
            }
            
            // 6. Create Line Object
            let finalLineString = currentLineWords.joined(separator: " ")
            let attr = NSAttributedString(string: finalLineString, attributes: attributes)
            let ctLine = CTLineCreateWithAttributedString(attr)
            let actualWidth = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
            
            // Calculate Position (Centered Horizontally)
            let safeLeft = minX + padding
            let extraSpace = availableWidth - actualWidth
            let xPos = safeLeft + (extraSpace / 2) // Center It
            // Y Position: CoreText draws at baseline.
            // Our currentY is the "bottom" of the conceptual line slot?
            // Or better: currentY is the conceptual center?
            // Let's use currentY as the visual vertical center of the line.
            // CTLine origin is baseline.
            // Baseline = Center + (Ascent-Descent)/2 - Ascent? No.
            // Baseline = currentY + (ascent - descent)/2 ... wait.
            // Let's just say currentY is the BASELINE location we aimed for.
            
            lines.append(LaidOutLine(
                text: finalLineString,
                position: CGPoint(x: xPos, y: currentY),
                width: actualWidth,
                ctLine: ctLine
            ))
            
            currentY += lineHeight
        }
        
        // 7. Validation
        if currentWordIndex < words.count {
            // Failed to fit all words
            return nil
        }
        
        // 8. Vertical Centering Post-Pass
        // We fit all texts, but they might be top-aligned in the bubble if we had extra space at bottom.
        // We calculate the used height and shift everything down to center in the boundingBox.
        // BoundingBox CenterY vs Used Block CenterY.
        
        if let firstLine = lines.first, let lastLine = lines.last {
            // Top of first line (approx)
            let textTop = firstLine.position.y - ascent
            let textBottom = lastLine.position.y - descent // (minus negative = plus)
            let _ = textTop - textBottom // This was `let textBlockHeight = textTop - textBottom`
            // (Coordinate system flipped? No, CoreGraphics is usually bottom-left origin, but standard UIKit/Vision is Top-Left).
            // Wait, path.contains assumes standard coordinate system of the path.
            // If path comes from Vision (0,0 bottom-left) normalized... but we converted it to View Coords (0,0 top-left).
            // In View Coords (Top-Left 0,0), Y increases downwards.
            // So Top is min Y, Bottom is max Y.
            
            // currentY was increasing. So firstLine has min Y? No, boundingBox.minY + lineHeight.
            // So firstLine is at TOP. lastLine is at BOTTOM.
            // firstLine.y is baseline. Ascent is ABOVE baseline (negative Y?).
            // In standard flipped UI (Top-Left 0,0):
            // Baseline is Y. Ascent goes UP (Lower Y). Descent goes DOWN (Higher Y).
            // So TextTop = firstLine.y - ascent.
            // TextBottom = lastLine.y + descent (if descent is positive length).
            // UIFont.descender is usually negative. So lastLine.y - descent = visual bottom.
            
            let blockTop = firstLine.position.y - ascent
            let blockBottom = lastLine.position.y - descent // (minus negative = plus)
            let blockHeight = blockBottom - blockTop
            let blockCenterY = blockTop + (blockHeight / 2)
            
            // Bubble Center Logic
            // We want to center strictly within the USED vertical range (the lines we effectively wrote to)?
            // Or center within the bounding Box?
            // Ideally center within Bounding Box.
            
            let bubbleCenterY = boundingBox.midY
            let shiftY = bubbleCenterY - blockCenterY
            
            // Apply Shift
            let centeredLines = lines.map { line in
                LaidOutLine(
                    text: line.text,
                    position: CGPoint(x: line.position.x, y: line.position.y + shiftY),
                    width: line.width,
                    ctLine: line.ctLine
                )
            }
            
            // Check if shift pushed lines out of path?
            // If the shape is very irregular (e.g. triangle), shifting might hit edges.
            // But usually vertical shifting is safe for ovals.
            // For robustness, we could re-verify, but let's trust standard centering for now.
            
            return LaidOutText(lines: centeredLines, totalHeight: blockHeight, fontSize: fontSize)
        }
        
        return nil
    }
}
