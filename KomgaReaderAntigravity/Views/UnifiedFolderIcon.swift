
import SwiftUI

struct UnifiedFolderIcon: View {
    let node: LocalFolderNode
    
    var body: some View {
        VStack(spacing: 0) {
            // 1. The Graphic Object (Box)
            LocalFolderCard(node: node)
                .frame(height: 180) 
            
            // 2. The Title (Below Box)
            MarqueeText(text: Series.formatSeriesName(node.name), font: .caption.bold())
                .foregroundColor(.white)
                .frame(width: 140) // Constrain width explicitly
                .clipped() // Force Clip to prevent overflow
                .padding(.top, 22) // Adjustable: Distance from Box to Title
            
            // 3. Item Count
            Text("\(node.books.count + node.children.count) items")
                .font(.caption2)
                .foregroundColor(.gray)
                .padding(.top, 0) // Adjustable: Distance from Title to Count
        }
        .frame(width: 150) // Standardize width for grid item
    }
}
