import SwiftUI

struct ReaderOverlayView: View {
    let balloons: [GeminiService.TranslatedBalloon]
    let imageSize: CGSize
    let displayedSize: CGSize // The actual size of the image on screen
    var showOriginal: Bool = false // Toggle between Original OCR and Translated
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(balloons) { balloon in
                    let rect = calculateRect(for: balloon.boundingBox, displayedSize: displayedSize)
                    
                    ZStack {
                        // Balloon Background (semi-transparent for overlay)
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.95))
                            .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                        
                        // Text: Original or Translated
                        Text(showOriginal ? balloon.originalText : balloon.translatedText)
                            .font(.system(size: calculateFontSize(for: rect), weight: .medium, design: .rounded))
                            .foregroundColor(.black)
                            .multilineTextAlignment(.center)
                            .padding(4)
                            .minimumScaleFactor(0.5)
                    }
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                }
            }
        }
        .allowsHitTesting(false) // Let touches pass through to zoom/pan
    }
    
    // Convert 1000x1000 normalized coordinates to displayed size
    // Convert 1000x1000 normalized coordinates to displayed size (Aspect Fit)
    private func calculateRect(for box: GeminiService.BoundingBox, displayedSize: CGSize) -> CGRect {
        // Calculate Render Rect manually (Aspect Fit logic)
        let imageAspectRatio = imageSize.width / imageSize.height
        let viewAspectRatio = displayedSize.width / displayedSize.height
        
        var renderRect = CGRect.zero
        
        if imageAspectRatio > viewAspectRatio {
            // Image wider -> Fits Width, Letterboxed Height
            let scale = displayedSize.width / imageSize.width
            let renderHeight = imageSize.height * scale
            let yOffset = (displayedSize.height - renderHeight) / 2
            renderRect = CGRect(x: 0, y: yOffset, width: displayedSize.width, height: renderHeight)
        } else {
            // Image taller -> Fits Height, Pillarboxed Width
            let scale = displayedSize.height / imageSize.height
            let renderWidth = imageSize.width * scale
            let xOffset = (displayedSize.width - renderWidth) / 2
            renderRect = CGRect(x: xOffset, y: 0, width: renderWidth, height: displayedSize.height)
        }
        
        // Map 1000-grid to RenderRect
        let x = renderRect.minX + (CGFloat(box.xmin) / 1000.0 * renderRect.width)
        let y = renderRect.minY + (CGFloat(box.ymin) / 1000.0 * renderRect.height)
        let w = (CGFloat(box.xmax) - CGFloat(box.xmin)) / 1000.0 * renderRect.width
        let h = (CGFloat(box.ymax) - CGFloat(box.ymin)) / 1000.0 * renderRect.height
        
        return CGRect(x: x, y: y, width: w, height: h)
    }
    
    private func calculateFontSize(for rect: CGRect) -> CGFloat {
        // Simple heuristic: font size relative to balloon height
        return max(8, rect.height * 0.15)
    }
}
