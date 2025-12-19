import SwiftUI
import PhotosUI

struct GeminiTestView: View {
    @State private var selectedImage: UIImage?
    @State private var balloons: [GeminiService.TranslatedBalloon] = []
    @State private var isAnalyzing: Bool = false
    @State private var errorMessage: String?
    
    @State private var selectedItem: PhotosPickerItem?
    
    var body: some View {
        VStack {
            if let image = selectedImage {
                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .overlay(
                            GeometryReader { geometry in
                                ForEach(balloons) { balloon in
                                    let rect = balloon.boundingBox.toCGRect(imageSize: geometry.size)
                                    
                                    ZStack {
                                        // Bounding Box
                                        Rectangle()
                                            .path(in: rect)
                                            .stroke(colorForShape(balloon.shape), lineWidth: 2)
                                        
                                        // Label
                                        Text(balloon.translatedText)
                                            .font(.caption)
                                            .padding(4)
                                            .background(Color.black.opacity(0.7))
                                            .foregroundColor(.white)
                                            .offset(x: rect.origin.x, y: rect.origin.y - 20)
                                    }
                                }
                            }
                        )
                }
                .frame(maxHeight: 500)
            } else {
                ContentUnavailableView("No Image Selected", systemImage: "photo.badge.plus")
            }
            
            HStack {
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label("Select Image", systemImage: "photo")
                }
                .onChange(of: selectedItem) { newItem in
                    Task {
                        if let data = try? await newItem?.loadTransferable(type: Data.self),
                           let uiImage = UIImage(data: data) {
                            selectedImage = uiImage
                            balloons = []
                        }
                    }
                }
                
                Button(action: analyzeImage) {
                    if isAnalyzing {
                        ProgressView()
                    } else {
                        Label("Analyze with Gemini", systemImage: "sparkles")
                    }
                }
                .disabled(selectedImage == nil || isAnalyzing)
                .buttonStyle(.borderedProminent)
            }
            .padding()
            
            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .padding()
            }
            
            List(balloons) { balloon in
                VStack(alignment: .leading) {
                    Text("🇮🇹 \(balloon.translatedText)").bold()
                    Text("🇺🇸 \(balloon.originalText)").font(.caption).foregroundColor(.gray)
                    Text("Shape: \(balloon.shape.rawValue)").font(.caption2)
                }
            }
        }
    }
    
    private func analyzeImage() {
        guard let image = selectedImage else { return }
        
        isAnalyzing = true
        errorMessage = nil
            
        Task {
            do {
                let results = try await GeminiService.shared.analyzeComicPage(image: image)
                await MainActor.run {
                    self.balloons = results
                    self.isAnalyzing = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isAnalyzing = false
                }
            }
        }
    }
    
    private func colorForShape(_ shape: GeminiService.BalloonShape) -> Color {
        switch shape {
        case .oval: return .blue
        case .rectangle: return .green
        case .cloud: return .orange
        case .jagged: return .red
        }
    }
}
