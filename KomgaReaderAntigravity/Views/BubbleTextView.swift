import SwiftUI
import UIKit
import CoreText

struct BubbleTextView: UIViewRepresentable {
    let text: String
    let path: Path
    let fontStyle: String
    let color: UIColor
    
    func makeUIView(context: Context) -> BubbleLabel {
        let view = BubbleLabel()
        view.backgroundColor = .clear
        return view
    }
    
    func updateUIView(_ uiView: BubbleLabel, context: Context) {
        uiView.text = text
        uiView.customPath = path.cgPath
        uiView.fontStyle = fontStyle
        uiView.textColor = color
        uiView.setNeedsDisplay()
    }
}

class BubbleLabel: UIView {
    var text: String = ""
    var customPath: CGPath?
    var fontStyle: String = "normal"
    var textColor: UIColor = .black
    
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), let path = customPath else { return }
        
        // Flip coordinate system (CoreText is bottom-up)
        context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.size.height)
        context.scaleBy(x: 1.0, y: -1.0)
        
        // Determine Base Font Name (using condensed fonts for better fitting)
        let fontName: String
        var forceUppercase = true
        
        switch fontStyle {
        case "shout":
            fontName = "Impact"
        case "computer":
            fontName = "CourierNewPSMT"
            forceUppercase = false
        case "italic", "whisper":
            fontName = "HelveticaNeue-Italic" 
            forceUppercase = false
        case "handwritten":
            fontName = "Noteworthy-Light"
            forceUppercase = false
        default:
            fontName = "HelveticaNeue-Medium" // Condensed, readable
            forceUppercase = false
        }
        
        let processedText = forceUppercase ? text.uppercased() : text
        
        print("🎈 BubbleTextView rendering: '\(processedText)' with style '\(fontStyle)'")
        
        // Use TextLayoutService for Scanline Layout
        if let layout = TextLayoutService.shared.layoutText(processedText, in: path, fontName: fontName, minSize: 10, maxSize: 50) {
            print("✅ Layout successful: \(layout.lines.count) lines, fontSize: \(layout.fontSize)")
            
            for line in layout.lines {
                // Coordinate Flip Correction
                // Layout calculated Y from Top (Standard UI).
                // Context is flipped (Bottom-Up).
                // We need to invert Y relative to the view height.
                // CTLine position is baseline. 
                // We assumed line.position.y is baseline in Top-Down.
                // So in Bottom-Up: newY = height - oldY
                
                let flippedY = bounds.size.height - line.position.y
                context.textPosition = CGPoint(x: line.position.x, y: flippedY)
                
                // Set text color
                context.setFillColor(textColor.cgColor)
                
                CTLineDraw(line.ctLine, context)
            }
        } else {
            print("❌ Layout FAILED for text: '\(processedText)'")
        }
    }
}
