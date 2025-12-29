import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @EnvironmentObject var appState: AppState // Fullscreen control
    @ObservedObject var gemini = GeminiService.shared // New: Monitor
    
    init() {
        // Customize Segmented Control Appearance
        // Customize Segmented Control Appearance
        let font = UIFont.systemFont(ofSize: 16, weight: .medium) // Reduced by further 8% (was 17), Unstretched
        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor.darkGray
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.white, .font: font], for: .selected)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.gray, .font: font], for: .normal)
        UISegmentedControl.appearance().backgroundColor = UIColor.black.withAlphaComponent(0.5)
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top Bar (Hidden in Fullscreen)
                if !appState.isFullScreen {
                    HStack {
                        // Unused Left Hamburger removed
                        // Button(action: {}) { ... }
                        
                        // Spacer to center picker if leading items are removed, or just standard Spacer
                        Spacer()
                        
                        Picker("", selection: $selectedTab) {
                            Text("Libreria").tag(0)
                            Text("Importa").tag(1)
                            Text("Opzioni").tag(2)
                            Text("Aiuto").tag(3)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(width: 380) // Reduced width for 4 tabs
                        // Removed scaleEffect(x: 1, y: 1.2) to prevent font stretching
                        .padding(.top, 0) // Removed extra offset
                        
                        Spacer()
                        
                        // Status Indicator
                        Spacer()
                    }
                    .padding(.horizontal) // Keep horizontal padding
                    .padding(.top, 5) // Minimal top padding (approx 1 unit in 40-grid if unit~20pt)
                    .padding(.bottom, 10)
                    // Zone 1 Background: Elegant Gradient
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.black.opacity(0.8), Color.black.opacity(0.6)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .zIndex(100)
                }
                
                // Content
                Group {
                    switch selectedTab {
                    case 0:
                        LocalLibraryView(refreshTrigger: selectedTab == 0)
                    case 1:
                        ContentView()
                    case 2:
                        SettingsView()
                    case 3:
                        HelpView()
                    default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            // Global Overlay
            DownloadStatusOverlay()
            
            // Gemini Quota Overlay (Bottom Right Floating)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    QuotaOverlayView()
                }
            }
            .allowsHitTesting(false)
        }
        .preferredColorScheme(.dark)
    }
}
