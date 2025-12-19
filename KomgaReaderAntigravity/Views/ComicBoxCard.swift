import SwiftUI

struct ComicBoxCard: View {
    // Content
    let coverImage: UIImage?
    // Theme Colors
    private let boxContainer = Color(red: 0.2, green: 0.3, blue: 0.45) // Gray-Blue Base
    private let boxLid = Color(white: 0.9) // White Lid
    private let handleColor = Color(red: 0.1, green: 0.1, blue: 0.2) // Dark Handle
    
    // Configuration
    var showBackground: Bool = true
    
    // Helper to process image (Crop Right Half if Landscape)
    private var processedImage: UIImage? {
        guard let original = coverImage else { return nil }
        
        // Check Aspect Ratio
        if original.size.width > original.size.height {
            // Landscape -> Crop Right Half (Standard Single Page View)
            let cropRect = CGRect(x: original.size.width / 2, y: 0, width: original.size.width / 2, height: original.size.height)
            if let cgImage = original.cgImage?.cropping(to: cropRect) {
                return UIImage(cgImage: cgImage, scale: original.scale, orientation: original.imageOrientation)
            }
        }
        return original
    }
    
    var body: some View {
        GeometryReader { geo in
            // Calculate available height for the box logic (Total minus top/bottom paddings)
            let boxHeight = geo.size.height - 20 
            let lidHeight = boxHeight * 0.22 // ~22% of the BOX, not the container
            let bodyHeight = boxHeight - lidHeight - 4 // -4 correction to align with Lid's shadow?
            // Actually, let's keep it simple: Lid + Body = BoxHeight. 
            // In original code there was a "Lid Lip Shadow". and lid overlap.
            // Let's stick to simple stacking:
            
            ZStack(alignment: .top) {
                // Background Container (Blue Card)
                if showBackground {
                    RoundedRectangle(cornerRadius: 6) 
                        .fill(boxContainer)
                }
                
                // The "Box" Graphic + Content
                // Positioned with padding to sit inside the blue card
                VStack(spacing: 0) {
                    
                    ZStack(alignment: .top) {
                        // MAIN CONTENT: The Image (Spanning Entire Box)
                if let cover = processedImage {
                    Image(uiImage: cover)
                        .resizable()
                        .scaledToFill() // Fill the width (since we constrain width below)
                        .frame(width: geo.size.width - 24) // Match the WIDEST part (Lid)
                        .frame(height: boxHeight, alignment: .top) // Clip to Box Height, Anchor at Top
                        
                        // Mask to Box Shape
                        .mask(
                            VStack(spacing: 0) {
                                // Lid Shape
                                RoundedCorner(radius: 4, corners: [.topLeft, .topRight])
                                    .frame(width: geo.size.width - 24, height: lidHeight)
                                
                                // Body Shape
                                Rectangle()
                                    .frame(width: geo.size.width - 32, height: boxHeight - lidHeight)
                            }
                        )
                        .clipped() // Crop overflow (Critical for bottom excess)
                } else {
                            // Placeholder Background
                            VStack(spacing: 0) {
                                Rectangle().fill(boxLid)
                                    .frame(width: geo.size.width - 24, height: lidHeight)
                                Rectangle().fill(Color.white)
                                    .frame(width: geo.size.width - 32, height: boxHeight - lidHeight)
                            }
                        }
                        
                        // 2. STROKE/DETAIL LAYER (Top)
                        VStack(spacing: 0) {
                            // LID FRAME
                            ZStack(alignment: .bottom) {
                                RoundedCorner(radius: 4, corners: [.topLeft, .topRight])
                                    .stroke(Color.black, lineWidth: 3)
                                
                                // Shadow Effect
                                Rectangle()
                                    .fill(LinearGradient(colors: [.clear, .black.opacity(0.3)], startPoint: .top, endPoint: .bottom))
                                    .frame(height: 4)
                            }
                            .frame(width: geo.size.width - 24, height: lidHeight)
                            
                            // BODY FRAME
                            ZStack {
                                Rectangle()
                                    .stroke(Color.black, lineWidth: 3)
                                
                                Rectangle()
                                    .strokeBorder(Color.gray.opacity(0.5), lineWidth: 1)
                                
                                Capsule()
                                    .fill(handleColor)
                                    .frame(width: 50, height: 18)
                                    .shadow(color: .white.opacity(0.5), radius: 1, x: 0, y: 1)
                                    .padding(.bottom, 50)
                            }
                            .frame(width: geo.size.width - 32, height: boxHeight - lidHeight)
                        }
                    }
                }
                .padding(.top, 10) // Push down the whole graphic assembly from the container top
                // Implicitly leaves 10 at bottom since height is Total - 20
            }
        }
        .frame(height: 180)
    }
}
