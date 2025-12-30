
import SwiftUI

// v6.0: Global Balloon Shape
struct BalloonShape: Shape {
    let type: ComicBalloonShape
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        switch type {
        case .oval:
            path.addEllipse(in: rect)
        case .rectangle:
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: 4, height: 4))
        case .cloud:
            // Simplified cloud logic
            let w = rect.width
            let h = rect.height
            path.addEllipse(in: CGRect(x: 0, y: h*0.2, width: w*0.4, height: h*0.6))
            path.addEllipse(in: CGRect(x: w*0.2, y: 0, width: w*0.6, height: h*0.7))
            path.addEllipse(in: CGRect(x: w*0.5, y: h*0.1, width: w*0.5, height: h*0.8))
            path.addEllipse(in: CGRect(x: w*0.1, y: h*0.4, width: w*0.8, height: h*0.6))
        case .jagged:
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
                
                if i == 0 { path.move(to: r1) }
                path.addLine(to: r2)
                path.addLine(to: CGPoint(x: centerX + cos(nextAngle) * w/2, y: centerY + sin(nextAngle) * h/2))
            }
            path.closeSubpath()
        }
        return path
    }
}

// v6.0: ReaderOverlayView
struct ReaderOverlayView: View {
    let imageSize: CGSize
    let balloons: [TranslatedBalloon]
    let showDebugShapes: Bool // Toggle for Green/Refined shapes
    
    // Legacy support for "ViewMode" logic can be simplified or removed if we rely on ReaderView's ZStack
    // But this View is designed to overlay strictly the balloons.
    
    var body: some View {
        GeometryReader { geometry in
            // Calculate Aspect Fit rect for the image within the view
            let renderRect = calculateRenderRect(for: imageSize, in: geometry.size)
            
            ZStack(alignment: .topLeading) {
                
                // Draw Balloons
                ForEach(balloons) { balloon in
                    Group {
                        if let localPath = balloon.localPath {
                            // Organic Shape from GrabCut
                            // We must scale AND translate to the renderRect position
                            let transform = CGAffineTransform(scaleX: renderRect.width, y: renderRect.height)
                                .concatenating(CGAffineTransform(translationX: renderRect.minX, y: renderRect.minY))
                            
                            let scaledPath = localPath.applying(transform)
                            
                            scaledPath
                                .fill(Color.white)
                                .shadow(color: .black.opacity(0.15), radius: 3, x: 1, y: 2)
                            
                        } else {
                            // Fallback: Elegant Rounded Rect
                            // calculateRect ALREADY includes renderRect.minX / minY offset.
                            // So we do NOT need an external offset.
                            let rect = calculateRect(for: balloon.box2D, renderRect: renderRect)
                            
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white)
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                                .shadow(color: .black.opacity(0.15), radius: 3, x: 1, y: 2)
                        }
                    }
                    // REMOVED INCORRECT .offset causing double-shift
                }
                
                // Draw Text (Separate Layer z-index)
                ForEach(balloons) { balloon in
                     let rect = calculateRect(for: balloon.box2D, renderRect: renderRect)
                     
                     // Text Container
                     // We use a much safer frame for text to avoid touching edges, especially for ovals/clouds
                     // Using proportional inset (8% of width/height) to ensure text stays inside but maximizes space
                     let insetX = rect.width * 0.08
                     let insetY = rect.height * 0.08
                     let textFrame = rect.insetBy(dx: max(2, insetX), dy: max(2, insetY))
                    
                     Text(balloon.translatedText)
                        .font(.system(size: calculateFontSize(for: rect), weight: .semibold, design: .rounded))
                        .foregroundColor(.black)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .minimumScaleFactor(0.3) // Allow aggressive scaling down
                        .padding(0) // Padding handled by frame inset
                        .frame(width: textFrame.width, height: textFrame.height)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    // Calculates the frame of the image inside the view (Aspect Fit)
    private func calculateRenderRect(for imageSize: CGSize, in displayedSize: CGSize) -> CGRect {
        if imageSize.width == 0 || imageSize.height == 0 { return .zero }
        
        let imageAspectRatio = imageSize.width / imageSize.height
        let viewAspectRatio = displayedSize.width / displayedSize.height
        
        if imageAspectRatio > viewAspectRatio {
            // Limited by Width
            let scale = displayedSize.width / imageSize.width
            let renderHeight = imageSize.height * scale
            let yOffset = (displayedSize.height - renderHeight) / 2
            return CGRect(x: 0, y: yOffset, width: displayedSize.width, height: renderHeight)
        } else {
            // Limited by Height
            let scale = displayedSize.height / imageSize.height
            let renderWidth = imageSize.width * scale
            let xOffset = (displayedSize.width - renderWidth) / 2
            return CGRect(x: xOffset, y: 0, width: renderWidth, height: displayedSize.height)
        }
    }
    
    // Converts 1000x1000 Box to Screen Coordinates using RenderRect
    private func calculateRect(for box2D: [Int], renderRect: CGRect) -> CGRect {
        guard box2D.count >= 4 else { return .zero }
        let ymin = CGFloat(box2D[0]) / 1000.0
        let xmin = CGFloat(box2D[1]) / 1000.0
        let ymax = CGFloat(box2D[2]) / 1000.0
        let xmax = CGFloat(box2D[3]) / 1000.0
        
        let x = renderRect.minX + (xmin * renderRect.width)
        let y = renderRect.minY + (ymin * renderRect.height)
        let w = (xmax - xmin) * renderRect.width
        let h = (ymax - ymin) * renderRect.height
        
        return CGRect(x: x, y: y, width: w, height: h)
    }
    
    private func calculateFontSize(for rect: CGRect) -> CGFloat {
        let dimension = min(rect.height, rect.width)
        return max(10, dimension * 0.15)
    }
}
