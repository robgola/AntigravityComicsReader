import SwiftUI

struct StoryRecapView: View {
    // Passed in props (could be empty or partial)
    let series: String
    let number: String
    let volume: String
    let publisher: String
    let coverImage: UIImage?
    
    // Internal Editing State
    @State private var inputSeries: String = ""
    @State private var inputNumber: String = ""
    @State private var inputVolume: String = ""
    @State private var inputPublisher: String = ""
    
    @State private var isInputMode: Bool = true // Default to checking on appear
    
    @State private var recapText: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    
    // Dismissal
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            // Background
            Color(red: 0.1, green: 0.1, blue: 0.12)
                .ignoresSafeArea()
                .onTapGesture {
                    UIApplication.shared.endEditing()
                }
            
            VStack(spacing: 20) {
                // Header (Draggable indicator)
                Capsule()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 40, height: 6)
                    .padding(.top, 10)
                
                if isInputMode {
                    // --- INPUT FORM ---
                    ScrollView {
                        VStack(spacing: 24) {
                            Text("Missing Metadata")
                                .font(.title2.bold())
                                .foregroundColor(.white)
                                .padding(.top)
                            
                            Text("Please confirm or fill in the comic details to help Gemini generate the best recap.")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            
                            // Cover Preview
                            if let cover = coverImage {
                                Image(uiImage: cover)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(height: 150)
                                    .cornerRadius(8)
                                    .shadow(radius: 5)
                            }
                            
                            // Form Fields
                            VStack(spacing: 16) {
                                InputField(title: "Series", text: $inputSeries, placeholder: "e.g. Spider-Man")
                                
                                HStack(spacing: 16) {
                                    InputField(title: "Number", text: $inputNumber, placeholder: "#")
                                    InputField(title: "Volume", text: $inputVolume, placeholder: "Vol.")
                                }
                                
                                InputField(title: "Publisher", text: $inputPublisher, placeholder: "e.g. Marvel")
                            }
                            .padding(.horizontal)
                            
                            Button(action: {
                                startGeneration()
                            }) {
                                HStack {
                                    Image(systemName: "sparkles")
                                    Text("Generate Recap")
                                }
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(12)
                            }
                            .padding(.horizontal)
                            .padding(.top, 10)
                            
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                        }
                        .padding(.bottom, 40)
                    }
                    
                } else {
                    // --- RESULT VIEW ---
                    VStack(alignment: .leading, spacing: 20) {
                        // Top Metadata
                        HStack(alignment: .top, spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Story So Far...")
                                    .font(.title2)
                                    .bold()
                                    .foregroundColor(.white)
                                
                                Text(inputSeries) // Use input values
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(.top, 4)
                                
                                Text("#\(inputNumber) \(inputVolume.isEmpty ? "" : "Vol.\(inputVolume)")")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                
                                if !inputPublisher.isEmpty {
                                    Text(inputPublisher)
                                        .font(.caption)
                                        .foregroundColor(.gray.opacity(0.8))
                                        .padding(.top, 2)
                                }
                            }
                            
                            Spacer()
                            
                            if let cover = coverImage {
                                Image(uiImage: cover)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 80, height: 120)
                                    .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top)
                        
                        Divider().background(Color.gray.opacity(0.3))
                        
                        // Text Content
                        ScrollView {
                            if let error = errorMessage {
                                VStack(spacing: 16) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.largeTitle)
                                        .foregroundColor(.yellow)
                                    Text("Something went wrong")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Text(error)
                                        .font(.body)
                                        .foregroundColor(.gray)
                                        .multilineTextAlignment(.center)
                                        .padding()
                                    
                                    Button("Try Again") {
                                        isInputMode = true
                                        errorMessage = nil
                                    }
                                    .foregroundColor(.blue)
                                }
                                .padding(.top, 40)
                            } else {
                                Text(recapText)
                                    .font(.body)
                                    .foregroundColor(.white.opacity(0.9))
                                    .lineSpacing(6)
                                    .padding()
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            // Initialize fields
            inputSeries = series
            inputNumber = number
            setVolumeFromInput() // Handle Vol. prefix logic if needed
            inputPublisher = publisher
            
            // Check if we have enough info to auto-start?
            // "il file comicinfo.xls è all'interno... se il file non è presente o non ha le info necessaria apri un dialog box"
            // Heuristic: If we have Series AND Publisher, usually safe.
            // If Publisher is missing -> Input Mode.
            // If Series looks like a filename (contains .cbz) -> Input Mode.
            
            let isFilename = inputSeries.lowercased().hasSuffix(".cbz") || inputSeries.lowercased().hasSuffix(".cbr")
            let missingPublisher = inputPublisher.isEmpty || inputPublisher == "Unknown"
            
            if !isFilename && !missingPublisher {
                // We have good data, auto-start
                isInputMode = false
                startGeneration()
            } else {
                // Missing info, show input
                isInputMode = true
                
                // If series was filename, clean it up for the field
                if isFilename {
                    inputSeries = inputSeries.replacingOccurrences(of: ".cbz", with: "", options: .caseInsensitive)
                        .replacingOccurrences(of: ".cbr", with: "", options: .caseInsensitive)
                        .replacingOccurrences(of: "_", with: " ")
                }
            }
        }
    }
    
    private func setVolumeFromInput() {
        // passed volume might be "2024" or empty
        inputVolume = volume
    }
    
    private func startGeneration() {
        isInputMode = false
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let recap = try await GeminiService.shared.generateStoryRecap(
                    series: inputSeries,
                    number: inputNumber,
                    volume: inputVolume,
                    publisher: inputPublisher
                )
                await MainActor.run {
                    self.recapText = recap
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
}

// Reusable Input Component
struct InputField: View {
    let title: String
    @Binding var text: String
    var placeholder: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.bold())
                .foregroundColor(.gray)
            
            TextField(placeholder, text: $text)
                .padding(12)
                .background(Color(white: 0.15))
                .cornerRadius(8)
                .foregroundColor(.white)
        }
    }
}

extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
