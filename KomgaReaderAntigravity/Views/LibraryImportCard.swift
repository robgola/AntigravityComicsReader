
//
//  LibraryImportCard.swift
//  KomgaReaderAntigravity
//

import SwiftUI

struct LibraryImportCard: View {
    let libraryName: String
    let covers: [UIImage]
    
    // Theme Colors (Exact match to ComicBoxCard)
    private let boxContainer = Color(red: 0.2, green: 0.3, blue: 0.45)
    private let boxLid = Color(white: 0.9)
    private let handleColor = Color(red: 0.1, green: 0.1, blue: 0.2)
    
    // MARK: - SETTINGS (EDIT HERE)
    // Le impostazioni per modificare le proporzioni manualmente:
    
    // 1. Altezza totale della Card (Box + Testo)
    private let cardHeight: CGFloat = 200 
    
    // 2. Dimensione Maniglia (Handle)
    // Library Original: 50 x 18. Qui scalato x1.33 = 66 x 24.
    private let handleWidth: CGFloat = 66
    private let handleHeight: CGFloat = 24
    
    // 3. Spessore linee (Stroke)
    // Library Original: 3. Qui scalato = 4.
    private let strokeWidth: CGFloat = 4
    
    // 4. Posizione Maniglia (Padding dal fondo della scatola)
    // Library Original: 50. Qui scalato = 60.
    private let handleBottomPadding: CGFloat = 60
    
    // 5. Proporzione Coperchio (Lid)
    // 0.22 = 22% dell'altezza della scatola.
    private let lidRatio: CGFloat = 0.22
    
    // 6. Spostamento Testo (Padding Top del nome)
    private let textTopPadding: CGFloat = 10
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { geo in
                let boxHeight = geo.size.height - 20
                let lidHeight = boxHeight * lidRatio
                
                ZStack(alignment: .top) {
                    // 1. Background Container (Blue Card)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(boxContainer)
                    
                    // 2. The Box Assembly
                    VStack(spacing: 0) {
                        ZStack(alignment: .top) {
                            
                            // A. IMAGES (Masked to Box Shape)
                            ZStack {
                                if !covers.isEmpty {
                                    ForEach(Array(covers.enumerated()), id: \.offset) { index, img in
                                        // Crop/Process Logic (Inline)
                                        let displayImage: UIImage = {
                                            if img.size.width > img.size.height {
                                                let cropRect = CGRect(x: img.size.width/2, y: 0, width: img.size.width/2, height: img.size.height)
                                                if let cg = img.cgImage?.cropping(to: cropRect) {
                                                    return UIImage(cgImage: cg, scale: img.scale, orientation: img.imageOrientation)
                                                }
                                            }
                                            return img
                                        }()
                                        
                                        Color.clear
                                            .aspectRatio(0.66, contentMode: .fit)
                                            .overlay(
                                                Image(uiImage: displayImage)
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill),
                                                alignment: .trailing
                                            )
                                            .clipped()
                                            // Randomness (Increased Staggering)
                                            .rotationEffect(.degrees(Double((index * 13) % 30 - 15))) 
                                            .offset(x: CGFloat((index * 15) % 40 - 20))
                                    }
                                } else {
                                    // Placeholder
                                    VStack(spacing: 0) {
                                        Rectangle().fill(boxLid).frame(height: lidHeight)
                                        Rectangle().fill(Color.white)
                                    }
                                }
                            }
                            .frame(width: geo.size.width - 24, height: boxHeight)
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
                            .clipped()
                            
                            // B. STROKES / HANDLE (Overlay)
                             VStack(spacing: 0) {
                                // LID FRAME
                                ZStack(alignment: .bottom) {
                                    RoundedCorner(radius: 4, corners: [.topLeft, .topRight])
                                        .stroke(Color.black, lineWidth: strokeWidth)
                                    
                                    // Shadow Effect
                                    Rectangle()
                                        .fill(LinearGradient(colors: [.clear, .black.opacity(0.3)], startPoint: .top, endPoint: .bottom))
                                        .frame(height: 5)
                                }
                                .frame(width: geo.size.width - 24, height: lidHeight)
                                
                                // BODY FRAME
                                ZStack {
                                    Rectangle()
                                        .stroke(Color.black, lineWidth: strokeWidth)
                                    
                                    Rectangle()
                                        .strokeBorder(Color.gray.opacity(0.5), lineWidth: 1.5)
                                    
                                    Capsule()
                                        .fill(handleColor)
                                        .frame(width: handleWidth, height: handleHeight)
                                        .shadow(color: .white.opacity(0.5), radius: 1, x: 0, y: 1)
                                        .padding(.bottom, handleBottomPadding)
                                }
                                .frame(width: geo.size.width - 32, height: boxHeight - lidHeight)
                            }
                        }
                    }
                    .padding(.top, 12)
                }
            }
            .frame(height: cardHeight * 1.04)
            .scaleEffect(1.04)
            
            // Library Name (Scrolling Text)
            // Centered by ScrollingText's internal logic now
            ScrollingText(
                 text: libraryName,
                 font: .system(size: 20, weight: .bold, design: .rounded),
                 color: .white
            )
            .frame(height: 30)
            .clipped() // Keep strict clip
            .padding(.top, textTopPadding)
        }
    }
}
