import SwiftUI
import Combine
import AudioToolbox

struct SplashScreenView: View {
    @AppStorage("skipIntro") private var skipIntro: Bool = false
    @State private var isActive = false
    @State private var phase: SplashPhase = .loading
    
    // Animation States
    @State private var logoScale: CGFloat = 0.01
    @State private var logoOpacity: Double = 0.0
    @State private var chaosImages: [UIImage] = []
    @State private var visibleChaosIndex: Int = -1
    
    // Timer
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    @State private var timeElapsed: TimeInterval = 0
    
    @EnvironmentObject var appState: AppState // Ensure passed down
    
    enum SplashPhase {
        case loading
        case chaos
        case logo
        case finished
    }
    
    var body: some View {
        if isActive {
            MainTabView()
                .environmentObject(appState) // Explicitly pass if needed, but Environment flows down
        } else {
            ZStack {
                Color.black.ignoresSafeArea()
                
                // PHASE 1: CHAOS (Random Pages Overflowing)
                // Persist during Logo phase too
                if phase == .chaos || phase == .logo {
                    ZStack {
                        ForEach(0..<min(chaosImages.count, 15), id: \.self) { index in
                            if index <= visibleChaosIndex {
                                Image(uiImage: chaosImages[index])
                                    .resizable()
                                    .aspectRatio(contentMode: .fill) // Fill screen completely
                                    .frame(width: UIScreen.main.bounds.width * 1.5, height: UIScreen.main.bounds.height * 1.5) // Overflow
                                    .rotationEffect(.degrees(Double.random(in: -45...45))) // More drastic rotation
                                    .offset(
                                        x: CGFloat.random(in: -200...200),
                                        y: CGFloat.random(in: -400...400)
                                    )
                                    .opacity(0.8)
                                    .clipped()
                                    .transition(.opacity.combined(with: .scale(scale: 1.2)))
                            }
                        }
                    }
                    .ignoresSafeArea()
                }
                
                // PHASE 2: LOGO (Zoom from Center)
                if phase == .logo {
                    VStack {
                        // Updated Icon: Comic Style Cover
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(LinearGradient(gradient: Gradient(colors: [.red, .orange]), startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 140, height: 200)
                                .shadow(color: .black.opacity(0.5), radius: 10, x: 5, y: 5)
                            
                            // "Comic Binding" effect
                            Rectangle()
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 5, height: 200)
                                .offset(x: -60)
                            
                            Image(systemName: "text.bubble.fill")
                                .font(.system(size: 80))
                                .foregroundColor(.white)
                                .rotationEffect(.degrees(-10))
                        }
                        .scaleEffect(1.2)
                        .padding(.bottom, 30)
                        
                        Text("ANTIGRAVITY")
                            .font(Font.custom("ChalkboardSE-Bold", size: 50)) // Comic Style Font
                            .foregroundColor(.white)
                            .shadow(color: .black, radius: 5)
                            
                        Text("COMICS READER")
                            .font(Font.custom("ChalkboardSE-Bold", size: 30)) // Subtitle
                            .foregroundColor(.yellow) // Comic Accent
                            .shadow(color: .black, radius: 5)
                            
                        Text(AppConstants.appVersion)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.top, 10)
                    }
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)
                }
            }
            .onChange(of: isActive) { newValue in
                if newValue {
                     // Transitioned to Library. Now trigger background refresh for NEXT time.
                     SplashBackgroundService.shared.updateSplashCache()
                }
            }
            .onReceive(timer) { _ in
                guard !skipIntro, !chaosImages.isEmpty else { return } // Start timer only if images loaded
                
                timeElapsed += 0.1
                
                if phase == .chaos {
                    // Show one new image every 0.3s (Faster)
                    if Int(timeElapsed * 10) % 3 == 0 {
                        if visibleChaosIndex < chaosImages.count - 1 {
                            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                                visibleChaosIndex += 1
                                // AudioServicesPlaySystemSound(1103) // Optional click
                            }
                        }
                    }
                    
                    // After 5 seconds, switch to Logo
                    if timeElapsed > 5.0 {
                        withAnimation(.easeInOut(duration: 1.0)) {
                            phase = .logo
                        }
                        // Trigger Logo Animation
                        withAnimation(.easeOut(duration: 1.5).delay(0.2)) {
                            logoScale = 1.0
                            logoOpacity = 1.0
                        }
                    }
                } else if phase == .logo {
                    // Hold logo for 2.5s
                    if timeElapsed > 7.5 {
                        withAnimation {
                            isActive = true
                        }
                    }
                }
            }
            .onAppear {
                // 1. Check Skip Intro Immediately
                if skipIntro {
                    isActive = true
                    return
                }
                
                // 2. Check Cache
                Task {
                    let images = await SplashBackgroundService.shared.getSplashImages(count: 20)
                    
                    await MainActor.run {
                        if images.isEmpty {
                            // No cache? Skip animation, go to app, load later
                            print("🚀 No Splash Cache found. Skipping intro.")
                            self.isActive = true
                        } else {
                            // Cache found! Start animation.
                            self.chaosImages = images
                            self.phase = .chaos
                        }
                    }
                }
            }
        }
    }
}

