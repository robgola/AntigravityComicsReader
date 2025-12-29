import SwiftUI

struct BalloonShape: Shape {
    let type: GeminiService.BalloonShape
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        switch type {
        case .oval:
            path.addEllipse(in: rect)
        case .rectangle:
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: 4, height: 4))
        case .cloud:
            // Simplified cloud: a few overlapping ellipses
            let w = rect.width
            let h = rect.height
            path.addEllipse(in: CGRect(x: 0, y: h*0.2, width: w*0.4, height: h*0.6))
            path.addEllipse(in: CGRect(x: w*0.2, y: 0, width: w*0.6, height: h*0.7))
            path.addEllipse(in: CGRect(x: w*0.5, y: h*0.1, width: w*0.5, height: h*0.8))
            path.addEllipse(in: CGRect(x: w*0.1, y: h*0.4, width: w*0.8, height: h*0.6))
        case .jagged:
            // Shouting balloon
            let centerX = rect.midX
            let centerY = rect.midY
            let w = rect.width
            let h = rect.height
            let points = 12
            for i in 0..<points {
                let angle = CGFloat(i) * (2 * .pi / CGFloat(points))
                let nextAngle = CGFloat(i + 1) * (2 * .pi / CGFloat(points))
                let midAngle = (angle + nextAngle) / 2
                
                let r1 = CGPoint(x: centerX + cos(angle) * w/2, y: centerY + sin(angle) * h/2)
                let r2 = CGPoint(x: centerX + cos(midAngle) * w/1.6, y: centerY + sin(midAngle) * h/1.6)
                
                if i == 0 {
                    path.move(to: r1)
                }
                path.addLine(to: r2)
                path.addLine(to: CGPoint(x: centerX + cos(nextAngle) * w/2, y: centerY + sin(nextAngle) * h/2))
            }
            path.closeSubpath()
        }
        
        return path
    }
}

struct ReaderOverlayView: View {
    let balloons: [GeminiService.TranslatedBalloon]
    let imageSize: CGSize
    let displayedSize: CGSize
    var showOriginal: Bool = false
    
    var body: some View {
        // Calculate the actual image area frame (handling aspect fit)
        let renderRect = calculateRenderRect(for: imageSize, in: displayedSize)
        
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                // SURGICAL MASKING LAYER (v3.0)
                // 1. We create a SINGLE drawing layer for all masks (Global Coordinates).
                ZStack(alignment: .topLeading) {
                ForEach(balloons) { balloon in
                     if let localPath = balloon.localPath {
                         // 1. ORGANIC SHAPE (High Priority - Hybrid Anchored)
                         // VISUAL DEBUG MODE: Solid Black, No Text
                         let scaledPath = localPath.applying(CGAffineTransform(scaleX: renderRect.width, y: renderRect.height))
                        
                        // Debug: Black Fill to verify shape match
                        scaledPath.fill(Color.black.opacity(0.7)) 
                        // scaledPath.stroke(Color.red, lineWidth: 1) // Optional: Red border to see edges better
                        
                     } else if let maskPath = balloon.textMaskPath {
                          // 2. SURGICAL MASK (Medium Priority)
                          // Fallback debug
                          let scaledPath = maskPath.applying(CGAffineTransform(scaleX: renderRect.width, y: renderRect.height))
                          scaledPath.fill(Color.black.opacity(0.7))
                     } else {
                         // 3. FALLBACK RECTANGLE (Low Priority)
                         // If organic detection fails, show the semantic box (what the user called "Almost Perfect" before)
                         let rect = calculateRect(for: balloon.boundingBox, renderRect: renderRect)
                         Path { path in
                             path.addRoundedRect(in: rect, cornerSize: CGSize(width: 5, height: 5))
                         }.fill(Color.black.opacity(0.7))
                     }
                }
            }
            .frame(width: renderRect.width, height: renderRect.height)
            .position(x: renderRect.midX, y: renderRect.midY)
            
            // 2. Text Layer (DISABLED for Shape Verification)
            // User requested to remove all text and focus on black overlays.
            /*
            ForEach(balloons) { balloon in
                let rect = calculateBalloonLayoutRect(balloon: balloon, renderRect: renderRect)
                
                ZStack {
                    // Translated Text
                    Text(showOriginal ? balloon.originalText : balloon.translatedText)
                        .font(.custom("Chalkboard SE Regular", size: calculateFontSize(for: rect)))
                        .foregroundColor(.black)
                        .multilineTextAlignment(.center)
                        .padding(2)
                        .lineLimit(nil)
                        .minimumScaleFactor(0.3)
                        .frame(width: rect.width, height: rect.height)
                }
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .transition(.opacity)
            }
            */
            }
        }
    }
    
    private func calculateBalloonLayoutRect(balloon: GeminiService.TranslatedBalloon, renderRect: CGRect) -> CGRect {
        if let maskPath = balloon.textMaskPath {
            // The mask path is normalized (0..1). Get its bounding box and scale to renderRect.
            let maskBounds = maskPath.boundingRect
            return CGRect(
                x: renderRect.minX + (maskBounds.minX * renderRect.width),
                y: renderRect.minY + (maskBounds.minY * renderRect.height),
                width: maskBounds.width * renderRect.width,
                height: maskBounds.height * renderRect.height
            )
        } else {
            // Fallback: Use Gemini Semantic Box
            return calculateRect(for: balloon.boundingBox, renderRect: renderRect)
        }
    }
    
    private func calculateRenderRect(for imageSize: CGSize, in displayedSize: CGSize) -> CGRect {
        let imageAspectRatio = imageSize.width / imageSize.height
        let viewAspectRatio = displayedSize.width / displayedSize.height
        
        if imageAspectRatio > viewAspectRatio {
            let scale = displayedSize.width / imageSize.width
            let renderHeight = imageSize.height * scale
            let yOffset = (displayedSize.height - renderHeight) / 2
            return CGRect(x: 0, y: yOffset, width: displayedSize.width, height: renderHeight)
        } else {
            let scale = displayedSize.height / imageSize.height
            let renderWidth = imageSize.width * scale
            let xOffset = (displayedSize.width - renderWidth) / 2
            return CGRect(x: xOffset, y: 0, width: renderWidth, height: displayedSize.height)
        }
    }
    
    private func calculateRect(for box: GeminiService.BoundingBox, renderRect: CGRect) -> CGRect {
        let x = renderRect.minX + (CGFloat(box.xmin) / 1000.0 * renderRect.width)
        let y = renderRect.minY + (CGFloat(box.ymin) / 1000.0 * renderRect.height)
        let w = (CGFloat(box.xmax) - CGFloat(box.xmin)) / 1000.0 * renderRect.width
        let h = (CGFloat(box.ymax) - CGFloat(box.ymin)) / 1000.0 * renderRect.height
        
        return CGRect(x: x, y: y, width: w, height: h)
    }
    
    // Legacy/Helper for compatibility if needed, but we use renderRect internally now
    private func calculateRect(for box: GeminiService.BoundingBox, displayedSize: CGSize) -> CGRect {
        let renderRect = calculateRenderRect(for: imageSize, in: displayedSize)
        return calculateRect(for: box, renderRect: renderRect)
    }
    
    private func calculateFontSize(for rect: CGRect) -> CGFloat {
        // Base on both height and width to avoid oversized text in narrow balloons
        let dimension = min(rect.height, rect.width)
        return max(10, dimension * 0.22)
    }
}
