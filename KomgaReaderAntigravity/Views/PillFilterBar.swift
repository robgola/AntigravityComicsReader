import SwiftUI

struct PillFilterBar: View {
    let tabs: [String]
    @Binding var selectedTab: String
    
    // Aesthetic Colors for tabs
    private let pillColors: [Color] = [.red, .blue, .orange, .green, .purple, .pink, .teal]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // "Tutte" (All) Tab
                Button(action: { selectedTab = "Tutte" }) {
                    Text("Tutte")
                        .font(.headline)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 20)
                        .background(selectedTab == "Tutte" ? Color.white : Color(white: 0.2))
                        .foregroundColor(selectedTab == "Tutte" ? .black : .white)
                        .cornerRadius(20)
                }
                
                // Dynamic Library Tabs
                ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                    let color = pillColors[index % pillColors.count]
                    let isSelected = selectedTab == tab
                    
                    Button(action: { selectedTab = tab }) {
                        Text(tab)
                            .font(.headline)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 20)
                            .background(
                                ZStack {
                                    if isSelected {
                                        color
                                    } else {
                                        RoundedRectangle(cornerRadius: 20)
                                            .stroke(color, lineWidth: 2)
                                            .background(Color(white: 0.1))
                                    }
                                }
                            )
                            .foregroundColor(.white)
                            .cornerRadius(20)
                            .shadow(color: isSelected ? color.opacity(0.6) : .clear, radius: 8, x: 0, y: 0) // Neon Glow
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }
}
