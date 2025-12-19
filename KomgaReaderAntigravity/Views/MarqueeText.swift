import SwiftUI
import UIKit // Required for UIFont

struct MarqueeText: View {
    let text: String
    let font: Font
    
    var body: some View {
        GeometryReader { geometry in
            let textWidth = text.widthOfString(usingFont: .preferredFont(forTextStyle: .caption1)) // Estimation
            let isOverflowing = textWidth > geometry.size.width
            
            ZStack(alignment: isOverflowing ? .leading : .center) {
                Text(text)
                    .font(font)
                    .fixedSize()
                    .modifier(ScrollingTextModifier(containerWidth: geometry.size.width, isOverflowing: isOverflowing, textWidth: textWidth))
                    .frame(width: geometry.size.width, alignment: isOverflowing ? .leading : .center)
            }
        }
        .frame(height: 20)
    }
}

struct ScrollingTextModifier: ViewModifier {
    let containerWidth: CGFloat
    let isOverflowing: Bool
    let textWidth: CGFloat
    @State private var offset: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .onAppear {
                if isOverflowing {
                    withAnimation(Animation.linear(duration: Double(textWidth) / 20.0).repeatForever(autoreverses: false)) {
                        offset = -textWidth - containerWidth // Scroll fully
                    }
                }
            }
    }
}



// MARK: - String Extension for Width
extension String {
    func widthOfString(usingFont font: UIFont) -> CGFloat {
        let fontAttributes = [NSAttributedString.Key.font: font]
        let size = self.size(withAttributes: fontAttributes)
        return size.width
    }
}
