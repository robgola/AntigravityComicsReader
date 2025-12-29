import SwiftUI

struct DebugLogView: View {
    let logContent: String
    let markedImage: UIImage? // Optional Debug Image
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let image = markedImage {
                        VStack(alignment: .leading) {
                            Text("OpenCV Marker Output:")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .border(Color.red, width: 2)
                        }
                    }
                    
                    Text("Raw JSON Response:")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text(logContent)
                        .font(.system(.caption, design: .monospaced))
                        .padding(.top, 4)
                        .textSelection(.enabled)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Gemini Debug Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        UIPasteboard.general.string = logContent
                    }) {
                        Image(systemName: "doc.on.doc")
                    }
                }
            }
        }
    }
}
