import SwiftUI

struct QuotaOverlayView: View {
    @ObservedObject var geminiService = GeminiService.shared
    
    // Free Tier Limit for Gemini 1.5 Flash
    let maxRequests = 1500
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 10))
                .foregroundColor(.yellow)
            
            Text("Quota:")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
            
            Text("\(geminiService.callCount) / \(maxRequests)")
                .font(.system(size: 10).monospacedDigit())
                .foregroundColor(quotaColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.6))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        )
        // Shadow for readability over detailed comics
        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
        .padding(8)
    }
    
    var quotaColor: Color {
        let percentage = Double(geminiService.callCount) / Double(maxRequests)
        if percentage > 0.9 { return .red }
        if percentage > 0.7 { return .orange }
        return .green
    }
}
