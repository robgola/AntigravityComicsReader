
import SwiftUI

struct ScrollingText: View {
    let text: String
    let font: Font
    let color: Color
    
    @State private var scrollOffset: CGFloat = 0
    @State private var contentWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    
    var body: some View {
        GeometryReader { geo in
            // Alignment: Leading if scrolling (overflow), Center if fitting
            ZStack(alignment: contentWidth > containerWidth ? .leading : .center) {
                Text(text)
                    .font(font)
                    .foregroundColor(color)
                    .lineLimit(1)
                    .fixedSize()
                    .background(GeometryReader { textGeo -> Color in
                        DispatchQueue.main.async {
                            self.contentWidth = textGeo.size.width
                            self.containerWidth = geo.size.width
                        }
                        return Color.clear
                    })
                    .offset(x: scrollOffset)
                    .onAppear {
                        withAnimation(Animation.linear(duration: 10.0).repeatForever(autoreverses: false)) {
                            // Only scroll if content is wider
                            if self.contentWidth > self.containerWidth {
                                self.scrollOffset = -self.contentWidth - 20 // Scroll fully out + gap
                            }
                        }
                    }
                    .onChange(of: contentWidth) { _ in
                        startAnimation()
                    }
                // Text logic...
            }
            .frame(width: geo.size.width, alignment: contentWidth > containerWidth ? .leading : .center) // Explicitly ensure ZStack fills the geo width
            .clipped()
        }
        .frame(height: 30) // Fixed height for the text line
    }
    
    private func startAnimation() {
         guard contentWidth > containerWidth else { 
             scrollOffset = 0
             return 
         }
         
         // Reset
         scrollOffset = containerWidth
         
         withAnimation(Animation.linear(duration: Double(contentWidth) / 20).repeatForever(autoreverses: false)) {
             scrollOffset = -contentWidth
         }
    }
}
