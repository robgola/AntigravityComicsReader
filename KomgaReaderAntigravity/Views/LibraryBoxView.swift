import SwiftUI

struct LibraryBoxView: View {
    let name: String
    let coverImage: UIImage?
    
    // Proportions
    // Lid = 22% of total height (Drastically reduced as per user request to be "shorter")
    // Body = 78% of total height
    private let lidHeightRatio: CGFloat = 0.22
    private let bodyWidthRatio: CGFloat = 0.92
    
    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let totalW = geo.size.width
                let totalH = geo.size.height
                
                let lidH = totalH * lidHeightRatio
                let bodyH = totalH - lidH
                
                let lidW = totalW
                let bodyW = totalW * bodyWidthRatio
                
                ZStack(alignment: .top) {
                    
                    // 1. BODY (Bottom Layer)
                    ZStack {
                        // Interior White
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                        
                        // Image (Bottom Slice)
                        if let img = coverImage {
                            Image(uiImage: img)
                                .aspectRatio(0.66, contentMode: .fit)
                                .overlay(
                                    Image(uiImage: img)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill),
                                    alignment: .trailing
                                )
                                .clipped()
                        }
                        
                        // Handle Removed as per user request
                    }
                    .frame(width: bodyW, height: bodyH)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.black, lineWidth: 2)) // Thinner stroke for scale
                    .offset(y: lidH)
                    
                    // 2. LID (Top Layer)
                    ZStack {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white)
                        
                        // Image (Top Slice)
                        if let img = coverImage {
                            Image(uiImage: img)
                                .aspectRatio(0.66, contentMode: .fit)
                                .overlay(
                                    Image(uiImage: img)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill),
                                    alignment: .trailing
                                )
                                .clipped()
                                .padding(2) // Slight whitespace border on lid usually looks authentic
                        }
                    }
                    .frame(width: lidW, height: lidH)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.black, lineWidth: 2))
                    .zIndex(1)
                    .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 2) // Lid Shadow
                }
            }
            .aspectRatio(0.66, contentMode: .fit) // Keep the Box Aspect Ratio (2:3)
            
            // Text Label
            Text(name)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .foregroundColor(.white)
                .shadow(color: .black, radius: 2, x: 0, y: 1)
                .frame(maxWidth: .infinity, alignment: .top)
                .frame(height: 30) // Force 2-line height (approx for 10pt font)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
