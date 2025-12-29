
import SwiftUI

struct ContinueReadingCarouselView: View {
    let books: [LocalBook]
    @State private var currentIndex: Int = 0
    @State private var currentMetadata: ComicInfo?
    
    var body: some View {
        if books.isEmpty {
            EmptyView()
        } else {
            let book = books[currentIndex]
            
            ZStack {
                // Background: Blurred Cover
                if let cover = book.coverImage {
                    Image(uiImage: cover)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: 350)
                        .blur(radius: 20)
                        .opacity(0.3)
                        .clipped()
                        .mask(Rectangle()) // Confine to area
                } else {
                    Color.black.opacity(0.3) // Fallback
                }
                
                // Content Layer
                HStack(spacing: 20) {
                    // LEFT ARROW
                    Button(action: {
                        withAnimation {
                            if currentIndex > 0 { currentIndex -= 1 }
                        }
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(currentIndex > 0 ? .white : .gray.opacity(0.3))
                    }
                    .disabled(currentIndex == 0)
                    
                    // CARD CONTENT
                    HStack(alignment: .top, spacing: 24) {
                        // 1. Cover (Clickable -> Reader)
                        NavigationLink(destination: 
                            ComicReaderView(bookURL: book.url, bookId: book.id)
                                .toolbar(.hidden, for: .tabBar)
                        ) {
                            if let original = book.coverImage {
                                // Process Image (Crop Right Half if Landscape)
                                let cover: UIImage = {
                                    if original.size.width > original.size.height {
                                        let cropRect = CGRect(x: original.size.width / 2, y: 0, width: original.size.width / 2, height: original.size.height)
                                        if let cgImage = original.cgImage?.cropping(to: cropRect) {
                                            return UIImage(cgImage: cgImage, scale: original.scale, orientation: original.imageOrientation)
                                        }
                                    }
                                    return original
                                }()
                                
                                Image(uiImage: cover)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(height: 280) // Detailed View Height
                                    .cornerRadius(8)
                                    .shadow(radius: 8)
                            } else {
                                Rectangle()
                                    .fill(Color.gray)
                                    .frame(width: 180, height: 280)
                                    .overlay(Text("No Cover").foregroundColor(.white))
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // 2. Metadata
                        VStack(alignment: .leading, spacing: 8) {
                            // PRIORITIZE book.metadata for instant response, fallback to currentMetadata if async load is still pending or needed
                            if let info = book.metadata ?? currentMetadata {
                                Text(info.series.isEmpty ? book.title : info.series)
                                    .font(.title)
                                    .bold()
                                    .foregroundColor(.white)
                                
                                if !info.number.isEmpty {
                                    Text("#\(info.number)") // Removed space to match bold styling
                                        .font(.title2)
                                        .bold()
                                        .foregroundColor(.white)
                                }
                                
                                // Credits
                                Group {
                                    if let writer = info.writer, !writer.isEmpty {
                                        HStack(alignment: .top) {
                                            Text("Writer:").foregroundColor(.gray).frame(width: 80, alignment: .leading)
                                            Text(writer).foregroundColor(.white)
                                        }
                                    }
                                    if let penciller = info.penciller, !penciller.isEmpty {
                                        HStack(alignment: .top) {
                                            Text("Penciller:").foregroundColor(.gray).frame(width: 80, alignment: .leading)
                                            Text(penciller).foregroundColor(.white)
                                        }
                                    }
                                    if let inker = info.inker, !inker.isEmpty {
                                        HStack(alignment: .top) {
                                            Text("Inker:").foregroundColor(.gray).frame(width: 80, alignment: .leading)
                                            Text(inker).foregroundColor(.white)
                                        }
                                    }
                                }
                                .font(.caption)
                                
                                // Summary
                                if !info.summary.isEmpty {
                                    Text(info.summary)
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.8))
                                        .lineLimit(6)
                                        .padding(.top, 8)
                                }
                            } else {
                                // Loading or Fallback
                                Text(book.title)
                                    .font(.title)
                                    .bold()
                                    .foregroundColor(.white)
                                
                                Text("Loading details...")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    // RIGHT ARROW
                    Button(action: {
                        withAnimation {
                            if currentIndex < books.count - 1 { currentIndex += 1 }
                        }
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(currentIndex < books.count - 1 ? .white : .gray.opacity(0.3))
                    }
                    .disabled(currentIndex == books.count - 1)
                }
                .padding()
            }
            .frame(height: 350) // Fixed Height for the Section
            .cornerRadius(12)
            .background(Color.black.opacity(0.5)) // Darken background logic
            .onChange(of: currentIndex) { _ in
                loadMetadata(for: books[currentIndex])
            }
            .onAppear {
                loadMetadata(for: books[currentIndex])
            }
            .onChange(of: books.map(\.id)) { oldVal, newVal in
                currentIndex = 0 // Reset to start
                if !books.isEmpty {
                    loadMetadata(for: books[0])
                }
            }
        }
    }
    
    private func loadMetadata(for book: LocalBook) {
        // Reset
        currentMetadata = nil
        // Simple async load
        Task {
            // Check if ComicInfo.xml exists in the book.url directory
            if let info = ComicMetadataService.shared.parseComicInfo(at: book.url) {
                await MainActor.run {
                    self.currentMetadata = info
                }
            } else {
                // Fails silently if no info found
            }
        }
    }
}
