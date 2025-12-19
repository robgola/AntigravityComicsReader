import SwiftUI
import UIKit

struct BubbleText: UIViewRepresentable {
    let text: String
    let path: Path
    let containerSize: CGSize
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.textAlignment = .center
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        // 1. Setup Text with reasonable initial font
        // Heuristic: Area-based font sizing
        // Estimate area of ellipse ~ 0.8 * w * h
        let area = containerSize.width * containerSize.height * 0.8
        let charCount = max(1, Double(text.count))
        // Nominal area per character ~ 10x10 = 100?
        // sqrt(area / charCount) gives rough dimension.
        let rawFontSize = sqrt(area / (charCount * 0.6)) // 0.6 factor for density
        let fontSize = min(max(rawFontSize, 10), 40) // Clamp between 10 and 40
        
        uiView.font = UIFont.systemFont(ofSize: fontSize, weight: .bold)
        uiView.text = text
        uiView.textColor = .black
        
        // 2. Create Exclusion Path (Inverse of Balloon)
        // We want text INSIDE the balloon.
        // exclusionPaths defines where text CANNOT go.
        // Trick: Exclude the "Outer Rectangle" MINUS the "Balloon Path" (Hole).
        
        let fullRectPath = UIBezierPath(rect: CGRect(origin: .zero, size: containerSize))
        
        // Convert SwiftUI Path to UIBezierPath
        let balloonBezier = UIBezierPath(cgPath: path.cgPath)
        
        // Transform balloon path to be relative to the container logic?
        // The 'path' passed in is likely in global view coordinates or normalized?
        // Wait, from ReaderView: "let scaledPath = ScaledPath..." -> "pathInView".
        // "pathInView.boundingRect" is the textRect.
        // So the 'path' we pass here should be normalized to (0,0) of this view?
        
        // We need the path to be relative to the TextView's bounds (0,0 to width,height).
        // If we pass the 'pathInView', its origin is (midX, midY)...
        // We need to translate it so its bounding box origin is at (0,0).
        
        let pathBounds = path.boundingRect
        let translate = CGAffineTransform(translationX: -pathBounds.minX, y: -pathBounds.minY)
        balloonBezier.apply(translate)
        
        // Append balloon to full rect
        fullRectPath.append(balloonBezier)
        
        // Use EvenOdd rule: Points inside Rect (1) are excluded. Points inside Balloon (1+1=2) are included.
        fullRectPath.usesEvenOddFillRule = true
        
        uiView.textContainer.exclusionPaths = [fullRectPath]
        
        // Auto-Resize Font pass?
        // If content size > bounds, shrink font?
        // Simple iteration
        fitText(in: uiView, size: fontSize)
    }
    
    private func fitText(in textView: UITextView, size: CGFloat) {
        var currentSize = size
        let minSize: CGFloat = 8
        
        // Try to fit. If content height > container height, shrink.
        // Warning: This can be slow. Limit iterations.
        for _ in 0..<5 {
            let fittingSize = textView.sizeThatFits(CGSize(width: containerSize.width, height: CGFloat.greatestFiniteMagnitude))
            
            if fittingSize.height <= containerSize.height {
                break // Fits!
            }
            
            currentSize -= 2
            if currentSize < minSize { currentSize = minSize; break }
            textView.font = UIFont.systemFont(ofSize: currentSize, weight: .bold)
        }
    }
}
