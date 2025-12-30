
import SwiftUI
import Vision

struct ComicReaderView: View {
    let initialBookURL: URL
    let initialBookId: String? // Optional
    
    @State private var activeBookURL: URL
    @State private var activeBookId: String?
    
    @State private var pages: [URL] = []
    @State private var currentPageIndex = 0
    // New Interactive UI State
    enum TranslationMode {
        case original // Clean image
        case sourceText // Show OCR text box below balloon
        case translatedOverlay // Show translated bubble over original
    }
    
    @State private var translationMode: TranslationMode = .original
    @State private var selectedBalloonID: UUID? // Track which balloon is active
    
    // Legacy State (Refactoring...)
    // @State private var viewMode: ReaderPageView.ReaderViewMode = .original 
    
    @State private var translationHistory = ""
    @State private var translatedOverlays: [TranslatedOverlay] = []
    @State private var isTranslating = false
    @ObservedObject private var geminiService = GeminiService.shared
    
    // Manual Selection State
    @State private var candidates: [TextCluster] = []
    @State private var selectedCandidateIndices: Set<Int> = []
    @State private var isSelectionMode = false
    @State private var rawObservations: [CGRect] = [] // Debug: Raw Vision Rects
    @State private var filteredRects: [CGRect] = [] // Debug: Filtered Rects
    @State private var bubbleRects: [CGRect] = [] // Debug: Bubble Rects
    @State private var showDebug = false

    @State private var showMenu = false // Toggle for overlay menu
    @State private var showDebugLog = false // New Debug Modal
    
    // MARK: - New Interactive UI State
    @State private var showShareSheet = false
    @State private var sliderValue: Double = 0
    
    // Gemini Vision State
    @State private var visionBalloons: [TranslatedBalloon] = []
    @State private var isGeminiTranslating = false
    
    // Navigation State
    @State private var canGoPrevious = false
    @State private var canGoNext = false
    
    @Environment(\.dismiss) var dismiss // For closing the view
    @EnvironmentObject var appState: AppState // For fullscreen control
    
    // Internal Gesture Controls
    @State private var shouldSuppressTap = false
    
    init(bookURL: URL, bookId: String?) {
        self.initialBookURL = bookURL
        self.initialBookId = bookId
        _activeBookURL = State(initialValue: bookURL)
        _activeBookId = State(initialValue: bookId)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // LAYER 1: Fullscreen Comic Pages
                if pages.isEmpty {
                    VStack {
                        ProgressView("Loading pages...")
                        Text(activeBookURL.lastPathComponent)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    TabView(selection: $currentPageIndex) {
                        ForEach(0..<pages.count, id: \.self) { index in
                            pageView(for: index)
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .ignoresSafeArea()
                }
                
                // LAYER 2: Exact Positioning Controls (Floating)
                if !showMenu {
                    Group {
                        // Bottom Left Toggle
                        Button(action: {
                            if shouldSuppressTap { return }
                            switch translationMode {
                            case .original: translationMode = .sourceText
                            case .sourceText: translationMode = .translatedOverlay
                            case .translatedOverlay: translationMode = .original
                            }
                        }) {
                            Image(systemName: translationMode == .original ? "eye.slash" : (translationMode == .sourceText ? "text.bubble" : "eye.fill"))
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Circle().fill(Color.black.opacity(0.5)))
                                .shadow(radius: 4)
                        }
                        .position(x: 40, y: geometry.size.height - 40)
                        
                        // Gear/Settings (Always visible for opening menu)
                        Button(action: {
                            if shouldSuppressTap { return }
                            withAnimation(.easeInOut(duration: 0.3)) { showMenu.toggle() }
                        }) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Circle().fill(Color.black.opacity(0.3)))
                        }
                        .position(x: geometry.size.width - 26.5, y: 36)
                        
                        // Bottom Right Translate
                        Button(action: {
                            if shouldSuppressTap {
                                shouldSuppressTap = false
                                return
                            }
                            Task { await performGeminiTranslation() }
                        }) {
                            ZStack {
                                if isGeminiTranslating {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .frame(width: 24, height: 24)
                                } else {
                                    Image(systemName: "translate")
                                        .font(.system(size: 24))
                                        .foregroundColor(visionBalloons.isEmpty ? .white : .green)
                                }
                            }
                            .frame(width: 60, height: 60)
                            .background(Circle().fill(Color.blue.opacity(0.8)))
                            .shadow(radius: 4)
                        }
                        .position(x: geometry.size.width - 40, y: geometry.size.height - 40)
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.8)
                                .onEnded { _ in
                                    shouldSuppressTap = true
                                    Task { await performGeminiTranslation(force: true) }
                                }
                        )
                    }
                    .allowsHitTesting(true)
                }
                
                // LAYER 3: Menu Overlay (conditional) - Update Back/share positions? 
                // Keeping existing menu logic, but maybe update Buttons inside menu to match new layout?
                // For now, let's keep the menu as is, or remove redundant buttons.
                
                if showMenu {
                    ZStack {
                        // Dimmer background
                        Color.black.opacity(0.7)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.3)) { showMenu = false }
                            }
                        
                        // Overlay Content
                        VStack(spacing: 0) {
                            // Top Bar (Empty background to just hold buttons, or full strip?)
                            // User asked for exact alignment.
                            // We'll put standard Back / Info / Share here, aligned typically.
                            // BUT the "Gear" must match the floating position.
                            // So we shouldn't use a standard padded HStack unless we force the height/padding.
                            // Or we use the SAME absolute positioning logic for consistency.
                            
                            // Let's use a ZStack for the Top Bar area to guarantee alignment
                            ZStack(alignment: .top) {
                                Color.black.opacity(0.8)
                                    .frame(height: 80) // Approximate height to cover the controls
                                    .ignoresSafeArea(edges: .top)
                                
                                // Controls
                                Group {
                                    // Back Button (Left - usually standard nav position, but let's align with eye for symmetry?)
                                    // Or keep standard back button location? User didn't specify Back button position.
                                    // Let's put Back button at Left 26.5, Y 36 to replace the "Eye" when menu is open?
                                    // Or just keep standard.
                                    // "mettila esattamente nella stessa posizione" -> Gear button at same pos.
                                    
                                    Button(action: { dismiss() }) {
                                        Image(systemName: "chevron.left")
                                            .font(.system(size: 29))
                                            .foregroundColor(.white)
                                    }
                                    .position(x: 26.5, y: 36)
                                    
                                    // Center Info
                                    VStack(spacing: 4) {
                                        Text("\(currentPageIndex + 1) / \(pages.count)")
                                            .font(.system(size: 20, weight: .bold))
                                            .foregroundColor(.white)
                                        
                                        Text(cleanFilename(from: activeBookURL))
                                            .font(.body)
                                            .foregroundColor(.white.opacity(0.9))
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    .position(x: geometry.size.width / 2, y: 36 + 10)
                                    
                                    // Share (Offset Left of Gear)
                                    Button(action: { showShareSheet = true }) {
                                        Image(systemName: "square.and.arrow.up")
                                            .font(.system(size: 22))
                                            .foregroundColor(.white)
                                    }
                                    .position(x: geometry.size.width - 26.5 - 50, y: 36)
                                    
                                    // Translate (Offset Left of Share)
                                    Button(action: {
                                        if shouldSuppressTap {
                                            shouldSuppressTap = false
                                            return
                                        }
                                        Task { await performGeminiTranslation() }
                                    }) {
                                        ZStack {
                                            if isGeminiTranslating {
                                                ProgressView()
                                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            } else {
                                                Image(systemName: "translate")
                                                    .font(.system(size: 22))
                                                    .foregroundColor(visionBalloons.isEmpty ? .white : .green)
                                            }
                                        }
                                        .padding(8)
                                    }
                                    .position(x: geometry.size.width - 26.5 - 100, y: 36)
                                    .simultaneousGesture(
                                        LongPressGesture(minimumDuration: 0.8)
                                            .onEnded { _ in
                                                shouldSuppressTap = true
                                                Task { await performGeminiTranslation(force: true) }
                                            }
                                    )
                                    
                                    // Debug Log (Offset Left of Translate)
                                    Button(action: { showDebugLog = true }) {
                                        Image(systemName: "ladybug.fill")
                                            .font(.system(size: 22))
                                            .foregroundColor(.white) // Orange for Debug
                                            .padding(8)
                                    }
                                    .position(x: geometry.size.width - 26.5 - 150, y: 36)
                                    
                                    // Gear (Right 26.5/36 - EXACT MATCH)
                                    Button(action: {
                                        withAnimation(.easeInOut(duration: 0.3)) { showMenu.toggle() }
                                    }) {
                                        Image(systemName: "gearshape.fill")
                                            .font(.system(size: 22))
                                            .foregroundColor(.white)
                                            .padding(8)
                                    }
                                    .position(x: geometry.size.width - 26.5, y: 36)
                                }
                            }
                            .frame(height: 80)
                            
                            Spacer()
                            
                            // Bottom Bar
                            VStack(spacing: 16) {
                                // Slider
                                if !pages.isEmpty {
                                    Slider(value: Binding(
                                        get: { Double(currentPageIndex) },
                                        set: { currentPageIndex = Int($0) }
                                    ), in: 0...Double(pages.count - 1), step: 1)
                                    .accentColor(.white)
                                    .padding(.horizontal, 40)
                                }
                                
                                // Navigation Arrows
                                HStack {
                                    // PREVIOUS BOOK
                                    Button(action: { navigateToPreviousBook() }) {
                                        Image(systemName: "chevron.left")
                                            .font(.system(size: 28, weight: .bold))
                                            .foregroundColor(canGoPrevious ? .white : .gray)
                                            .padding()
                                    }
                                    .disabled(!canGoPrevious)
                                    
                                    Spacer()
                                    
                                    // Page navigation controls (Stepper)
                                    HStack(spacing: 30) {
                                        Button(action: {
                                            if currentPageIndex > 0 {
                                                withAnimation { currentPageIndex -= 1 }
                                            }
                                        }) {
                                            Image(systemName: "arrow.left")
                                                .font(.system(size: 20))
                                                .foregroundColor(.white)
                                        }
                                        
                                        Button(action: {
                                            if currentPageIndex < pages.count - 1 {
                                                withAnimation { currentPageIndex += 1 }
                                            }
                                        }) {
                                            Image(systemName: "arrow.right")
                                                .font(.system(size: 20))
                                                .foregroundColor(.white)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    // NEXT BOOK
                                    Button(action: { navigateToNextBook() }) {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 28, weight: .bold))
                                            .foregroundColor(canGoNext ? .white : .gray)
                                            .padding()
                                    }
                                    .disabled(!canGoNext)
                                }
                                .padding(.horizontal, 20)
                            }
                            .padding(.vertical, 30)
                            .padding(.bottom, 20)
                            .background(Color.black.opacity(0.8))
                            .ignoresSafeArea(edges: .bottom)
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if !pages.isEmpty && currentPageIndex < pages.count {
                ShareSheet(activityItems: [pages[currentPageIndex]])
            }
        }
        .sheet(isPresented: $showDebugLog) {
            DebugLogView(
                logContent: GeminiService.shared.lastRawResponse,
                markedImage: GeminiService.shared.lastMarkedImage
            )
        }
        .navigationBarHidden(true) // Legacy
        .statusBar(hidden: true) // Legacy
        .toolbar(.hidden, for: .navigationBar) // Modern
        .persistentSystemOverlays(.hidden) // Modern (iOS 16+) hides Home Indicator + Status Bar
        .onAppear {
            appState.isFullScreen = true
            updateNavigationStatus()
        }
        .onDisappear {
            appState.isFullScreen = false
        }
        .task {
            loadPages()
        }
        .onChange(of: activeBookURL) { _, _ in
            loadPages()
            updateNavigationStatus()
        }
        .onChange(of: currentPageIndex) { _, newPage in
            // Clear overlays on page change
            translatedOverlays = []
            visionBalloons = [] // Clear Gemini results
            isSelectionMode = false
            candidates = []
            selectedCandidateIndices = []
            sliderValue = Double(newPage)
            
            // Save reading progress
            if let bookId = activeBookId, !pages.isEmpty {
                ReadingProgressManager.shared.saveProgress(
                    bookId: bookId,
                    currentPage: newPage,
                    totalPages: pages.count
                )
            }
        }
    }
    
    private func shareCurrentPage() {
        showShareSheet = true
    }
    
    // MARK: - Navigation Helpers
    
    private func updateNavigationStatus() {
        let fileManager = FileManager.default
        let currentURL = activeBookURL
        let directory = currentURL.deletingLastPathComponent()
        
        do {
            let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { url in
                    let ext = url.pathExtension.lowercased()
                    if ["cbz", "cbr", "pdf", "epub"].contains(ext) { return true }
                    return (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            
            if let index = files.firstIndex(of: currentURL) {
                canGoPrevious = index > 0
                canGoNext = index < files.count - 1
            } else {
                canGoPrevious = false
                canGoNext = false
            }
        } catch {
            print("Error checking navigation status: \(error)")
            canGoPrevious = false
            canGoNext = false
        }
    }
    
    private func navigateToPreviousBook() {
        navigate(offset: -1)
    }
    
    private func navigateToNextBook() {
        navigate(offset: 1)
    }
    
    private func navigate(offset: Int) {
        let fileManager = FileManager.default
        let currentURL = activeBookURL
        let directory = currentURL.deletingLastPathComponent()
        
        do {
            let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { url in
                    let ext = url.pathExtension.lowercased()
                    if ["cbz", "cbr", "pdf", "epub"].contains(ext) { return true }
                    return (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            
            if let index = files.firstIndex(of: currentURL) {
                let newIndex = index + offset
                if newIndex >= 0 && newIndex < files.count {
                    let newURL = files[newIndex]
                    
                    // Reset State
                    currentPageIndex = 0
                    pages = []
                    translationMode = .original
                    activeBookURL = newURL
                    // Note: activeBookId becomes nil for local navigation unless we resolve it
                    activeBookId = nil 
                }
            }
        } catch {
            print("Navigation error: \(error)")
        }
    }
    
    private func pageView(for index: Int) -> some View {
        ReaderPageView(
            imageURL: pages[index],
            translationMode: translationMode, // Changed from viewMode
            overlays: index == currentPageIndex ? translatedOverlays : [],
            candidates: index == currentPageIndex && isSelectionMode ? candidates : [],
            selectedIndices: index == currentPageIndex && isSelectionMode ? $selectedCandidateIndices : .constant([]),
            rawObservations: index == currentPageIndex ? rawObservations : [],
            filteredRects: index == currentPageIndex ? filteredRects : [],
            bubbleRects: index == currentPageIndex ? bubbleRects : [],
            showDebug: index == currentPageIndex ? showDebug : false,
            showDebugLog: index == currentPageIndex ? showDebugLog : false,
            visionBalloons: index == currentPageIndex ? visionBalloons : []
        )
    }
    
    private func performGeminiTranslation(force: Bool = false) async {
        guard !pages.isEmpty, currentPageIndex < pages.count else { return }
        
        // Critical: Concurrency guard - must be synchronous-ish check
        if isGeminiTranslating && !force { return }
        
        // If already translated and NOT forcing, just toggle mode
        if !force && !visionBalloons.isEmpty {
            await MainActor.run {
                translationMode = (translationMode == .translatedOverlay) ? .original : .translatedOverlay
            }
            return
        }
        
        await MainActor.run {
            self.isGeminiTranslating = true
            // If forcing, clear current to show loading state
            if force {
                self.visionBalloons = []
            }
        }
        let currentImageURL = pages[currentPageIndex]
        
        // Persistence ID: Use BookID or Filename as fallback
        let persistenceId = activeBookId ?? activeBookURL.deletingPathExtension().lastPathComponent
        
        // 1. Check Cache
        if !force, let cachedBalloons = GeminiService.shared.loadTranslations(forBook: persistenceId, pageIndex: currentPageIndex) {
            print("📦 Using Cached Translations for Page \(currentPageIndex)")
            await MainActor.run {
                self.visionBalloons = cachedBalloons
                self.translationMode = .translatedOverlay
                self.isGeminiTranslating = false
            }
            return
        }
        
        guard let image = UIImage(contentsOfFile: currentImageURL.path) else {
            isGeminiTranslating = false
            return
        }
        
        // Capture current index to avoid race condition
        let capturedIndex = currentPageIndex
        
        do {
            // v6.0 Pipeline (YOLO + GrabCut + Gemini)
            let balloons = try await BalloonPipeline.shared.processPage(image: image)
            
            // 5. Save to Cache
            if !balloons.isEmpty {
                 GeminiService.shared.saveTranslations(balloons, forBook: persistenceId, pageIndex: currentPageIndex)
            }
            
            await MainActor.run {
                // GUARD: Ensure user hasn't moved away
                guard self.currentPageIndex == capturedIndex else {
                    print("⚠️ Result discarded: User moved from p\(capturedIndex) to p\(self.currentPageIndex)")
                    self.isGeminiTranslating = false
                    return
                }
                
                self.visionBalloons = balloons
                self.translationMode = .translatedOverlay
                self.isGeminiTranslating = false
            }
            
            // Trigger background prefetch for next pages (if still valid)
            if currentPageIndex == capturedIndex {
                prefetchNextPages(count: 2)
            }
            
        } catch {
            print("Gemini Translation Error: \(error)")
            await MainActor.run {
                self.isGeminiTranslating = false
            }
        }
    }
    
    // MARK: - Prefetching (v6.2)
    private func prefetchNextPages(count: Int) {
        guard !pages.isEmpty else { return }
        
        // Start from next page
        let start = currentPageIndex + 1
        let end = min(currentPageIndex + count, pages.count - 1)
        
        guard start <= end else { return }
        
        // Use BookID or Filename
        let persistenceId = activeBookId ?? activeBookURL.deletingPathExtension().lastPathComponent
        
        print("🔮 Prefetching pages \(start) to \(end)...")
        
        Task.detached(priority: .background) {
            for i in start...end {
                // 1. Check if already translated (Cache)
                if GeminiService.shared.loadTranslations(forBook: persistenceId, pageIndex: i) != nil {
                   print("   - Page \(i) already cached. Skipping.")
                   continue
                }
                
                // 2. Load Image
                // We need access to `pages` array. Since this is detached, we capture `pages` copy? 
                // Alternatively, use an Actor or duplicate logic. 
                // Since `pages` is [URL], it's safe to capture.
                // NOTE: We cannot access `self.pages` directly in detached task easily without capturing.
                // Let's rely on standard Task capturing self strongly or just passing data.
                // To keep it safe and simple, we'll execute the loop logic inside a Task that inherits context or carefully captures.
            }
        }
        
        // Better approach: Use local Task (inherits actor context) but yield? 
        // Or just fire and forget on MainActor? `BalloonPipeline` runs on background threads anyway.
        // Let's use `Task` which inherits MainActor (since we are in View/MainActor) but the pipeline calls are async.
        
        Task {
            for i in start...end {
                // Check Cache
                if GeminiService.shared.loadTranslations(forBook: persistenceId, pageIndex: i) != nil {
                    continue
                }
                
                // Load Image
                let pageURL = pages[i]
                guard let image = UIImage(contentsOfFile: pageURL.path) else { continue }
                
                print("   - Prefetching Page \(i) (Hybrid v6.1)...")
                do {
                    // Call Pipeline (Background)
                    let balloons = try await BalloonPipeline.shared.processPage(image: image)
                    if !balloons.isEmpty {
                        GeminiService.shared.saveTranslations(balloons, forBook: persistenceId, pageIndex: i)
                        print("   - Page \(i) Prefetch Complete & Saved.")
                        
                        // Optional: If we want to aggressively cache images for display, we could do it here,
                        // but GeminiService only saves JSON. That's fine.
                    }
                } catch {
                    print("   - Page \(i) Prefetch Failed: \(error)")
                }
            }
        }
    }
    
    private func loadPages() {
        // FileManager operations don't throw for enumerator, but we might want to wrap in do-catch if we were doing other things.
        // However, enumerator(at:includingPropertiesForKeys:) does not throw.
        // The previous do-catch was unnecessary.
        
        let fileManager = FileManager.default
        
        // Use activeBookURL instead of bookURL
        let url = activeBookURL
        
        // Recursive search for images
        var imageURLs: [URL] = []
        
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        
        // Support Directory-based comics (common in this app's context?)
        if isDirectory {
            if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil) {
                for case let fileURL as URL in enumerator {
                    if ["jpg", "jpeg", "png", "webp"].contains(fileURL.pathExtension.lowercased()) {
                        imageURLs.append(fileURL)
                    }
                }
            }
        } 
        // Support Archive checks? Not implementing full Unzip here unless requested.
        // Assuming Siblings are Directories too.
        
        pages = imageURLs.sorted { $0.lastPathComponent < $1.lastPathComponent }
        print("Found \(pages.count) pages for \(url.lastPathComponent)")
        
        // Save initial progress (or update lastReadDate) when opening
        // If we don't have ID, we default to page 0 (set above)
        if let bookId = activeBookId, !pages.isEmpty {
            ReadingProgressManager.shared.saveProgress(
                bookId: bookId,
                currentPage: currentPageIndex,
                totalPages: pages.count
            )
        }
    }
    
    private func startSelectionMode() {
        guard !pages.isEmpty else { return }
        isTranslating = true
        translatedOverlays = [] // Clear previous
        candidates = []
        selectedCandidateIndices = []
        isSelectionMode = true
        
        Task {
            await performOCR()
        }
    }
    
    private func performOCR() async {
        guard !pages.isEmpty else { return }
        let currentImageURL = pages[currentPageIndex]
        
        guard let image = UIImage(contentsOfFile: currentImageURL.path) else {
            isTranslating = false
            isSelectionMode = false
            return
        }
        
        do {
            // 1. Enhance image with OpenCV FIRST (before OCR)
            let enhancedImage = ImageProcessor.shared.enhanceForOCR(image: image)
            
            // 2. Normalize orientation
            guard let normalizedImage = VisionService.shared.normalizeImage(enhancedImage),
                  let cgImage = normalizedImage.cgImage else { return }
            
            // 3. Run OCR on enhanced, normalized image
            let request = VNRecognizeTextRequest()
            
            // Use Revision 3 (iOS 16+ "Live Text" engine)
            if #available(iOS 16.0, *) {
                request.revision = VNRecognizeTextRequestRevision3
            } else {
                request.revision = VNRecognizeTextRequestRevision2
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            
            // Maximize recognition for comics
            request.recognitionLanguages = ["en-US"] // Explicit English
            request.minimumTextHeight = 0.01 // Allow smaller text (sound effects, whispers)
            
            // Now we can use default orientation (.up) because we normalized the pixels
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])
            
            guard let observations = request.results else {
                print("No text observations found")
                isTranslating = false
                isSelectionMode = false
                return
            }
            
            // Filter out extremely large text (titles, etc.)
            
            await MainActor.run {
                self.rawObservations = observations.map { $0.boundingBox }
            }
            
            // Relaxed to 1.0 (Disabled) to rule out filtering
            let filteredObservations = observations.filter { obs in
                let h = obs.boundingBox.height
                let text = obs.topCandidates(1).first?.string.lowercased() ?? ""
                let confidence = obs.topCandidates(1).first?.confidence ?? 0
                
                // 0. Filter Low Confidence (False Positives)
                // Vision sometimes detects "ghost text" in shadows or textures
                if confidence < 0.5 { return false } // Require at least 50% confidence
                
                // 1. Filter Titles (Too big)
                if h > 0.15 { return false } // > 15% of page height is likely a title
                
                // 2. Filter Credits / Metadata
                if text.contains("written by") || text.contains("art by") || text.contains("letters by") || text.contains("colors by") { return false }
                if text.contains("•") || text.contains("|") { return false } // Separators often used in credits
                
                // 3. Filter Badges / Marketing
                if text.contains("preview") || text.contains("exclusive") || text.contains("edition") || text.contains("issue") { return false }
                if text.contains("www.") || text.contains(".com") { return false } // URLs
                
                // 4. Filter Single Words that are likely names or sounds (Heuristic)
                // If it's a single word and starts with capital, might be a name label.
                // But be careful not to filter "Help!" or "No!".
                // Let's rely on the "Name Entity Recognition" step for this later if needed.
                
                return true
            }
            
            await MainActor.run {
                self.filteredRects = filteredObservations.map { $0.boundingBox }
            }
            
            // 2. Detect Bubbles using BubbleDetector (Flood Fill - PROVEN METHOD)
            let detectedBubbles = await BubbleDetector.shared.detectBubbles(in: image, observations: filteredObservations)
            
            await MainActor.run {
                self.bubbleRects = detectedBubbles.map { $0.boundingBox }
            }
            
            // 3. Match Text to Bubbles
            var bubbleObs: [UUID: (bubble: DetectedBubble, observations: [VNRecognizedTextObservation])] = [:]
            var unassignedObservations: [VNRecognizedTextObservation] = []
            
            for obs in filteredObservations {
                let visionBox = obs.boundingBox
                let normRect = CGRect(
                    x: visionBox.minX,
                    y: 1.0 - visionBox.maxY,
                    width: visionBox.width,
                    height: visionBox.height
                )
                
                var bestMatch: DetectedBubble?
                var maxIntersectionArea: CGFloat = 0
                
                for bubble in detectedBubbles {
                    let expandedRect = bubble.boundingBox.insetBy(dx: -0.05, dy: -0.05)
                    let intersection = expandedRect.intersection(normRect)
                    let area = intersection.width * intersection.height
                    
                    if area > 0 && area > maxIntersectionArea {
                        maxIntersectionArea = area
                        bestMatch = bubble
                    }
                }
                
                if let match = bestMatch {
                    if var existing = bubbleObs[match.id] {
                        existing.observations.append(obs)
                        bubbleObs[match.id] = existing
                    } else {
                        bubbleObs[match.id] = (match, [obs])
                    }
                } else {
                    unassignedObservations.append(obs)
                }
            }
            
            // 4. Convert to TextCluster
            var newCandidates: [TextCluster] = []
            
            for (_, data) in bubbleObs {
                let sortedObs = data.observations.sorted { $0.boundingBox.minY > $1.boundingBox.minY }
                let joinedText = sortedObs.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
                let allRects = sortedObs.map { $0.boundingBox }
                
                newCandidates.append(TextCluster(
                    boundingBox: data.bubble.boundingBox,
                    text: joinedText,
                    rects: allRects,
                    bubblePath: data.bubble.path
                ))
            }
            
            // Handle unassigned text
            if !unassignedObservations.isEmpty {
                let fallbackClusters = clusterObservations(unassignedObservations)
                newCandidates.append(contentsOf: fallbackClusters)
            }
            
            await MainActor.run {
                self.candidates = newCandidates
                self.isTranslating = false
            }
        } catch {
            print("OCR error: \(error)")
            await MainActor.run {
                self.isTranslating = false
                self.isSelectionMode = false
            }
        }
    }
    
    private func confirmSelection() {
        isTranslating = true
        isSelectionMode = false
        
        Task {
            let selectedClusters = selectedCandidateIndices.map { candidates[$0] }
            var newOverlays: [TranslatedOverlay] = []
            
            for cluster in selectedClusters {
                let cleanedText = cleanOCRText(cluster.text)
                
                // Check Case
                // let isUppercased = cleanedText.filter { $0.isLetter }.allSatisfy { $0.isUppercase }
                
                let overlayID = UUID()
                let placeholderOverlay = TranslatedOverlay(
                    id: overlayID,
                    text: "...",
                    fontStyle: "normal",
                    boundingBox: cluster.boundingBox,
                    rects: cluster.rects,
                    path: cluster.bubblePath
                )
                newOverlays.append(placeholderOverlay)
                
                Task {
                    do {
                        // 1. Perform Translation
                        let result = try await GeminiService.shared.translate(text: cleanedText, context: translationHistory)
                        
                        await MainActor.run {
                            // Update history
                            translationHistory += "\n[Original]: \(cleanedText) -> [Translated]: \(result.translatedText) [Style]: \(result.fontStyle)"
                            
                            // Update Overlay
                            if let index = self.translatedOverlays.firstIndex(where: { $0.id == overlayID }) {
                                let updatedOverlay = self.translatedOverlays[index]
                                self.translatedOverlays[index] = TranslatedOverlay(
                                    id: updatedOverlay.id,
                                    text: result.translatedText,
                                    fontStyle: result.fontStyle,
                                    boundingBox: updatedOverlay.boundingBox,
                                    rects: updatedOverlay.rects,
                                    path: updatedOverlay.path
                                )
                            }
                        }
                    } catch {
                        print("Translation error: \(error)")
                        // Fallback to original text on error
                        await MainActor.run {
                            if let index = self.translatedOverlays.firstIndex(where: { $0.id == overlayID }) {
                                var updatedOverlay = self.translatedOverlays[index]
                                // keep "..." or revert? Let's show "Error" or original
                                updatedOverlay = TranslatedOverlay(
                                    id: updatedOverlay.id,
                                    text: cleanedText, // Revert
                                    fontStyle: "normal",
                                    boundingBox: updatedOverlay.boundingBox,
                                    rects: updatedOverlay.rects,
                                    path: updatedOverlay.path
                                )
                                self.translatedOverlays[index] = updatedOverlay
                            }
                        }
                    }
                }
            }
            
            await MainActor.run {
                self.translatedOverlays.append(contentsOf: newOverlays)
                self.translationMode = .sourceText // Show Original Text Box first
                self.isTranslating = false
                // Keep isSelectionMode = true so we can see the selected balloon?
                // Or maybe we should hide the unselected ones?
                // For now, let's keep selection mode active so user can select others?
                // User said "rischiaccio" (Confirm) -> Box appears.
                // If we keep selection mode, we can still select others.
                // But we need to make sure "Eye" button works.
            }
        }
    }
    
    private func clusterObservations(_ observations: [VNRecognizedTextObservation]) -> [TextCluster] {
        // Simple clustering based on distance
        var clusters: [TextCluster] = []
        
        // Sort by Y (top to bottom) - Vision Y is 0 at bottom, 1 at top. So higher Y is higher on page.
        // Let's sort top-down (descending Y)
        let sorted = observations.sorted { $0.boundingBox.minY > $1.boundingBox.minY }
        
        for obs in sorted {
            guard let text = obs.topCandidates(1).first?.string else { continue }
            // Convert Vision (Bottom-Left) to Normalized (Top-Left) for consistency
            let visionBox = obs.boundingBox
            let box = CGRect(
                x: visionBox.minX,
                y: 1.0 - visionBox.maxY,
                width: visionBox.width,
                height: visionBox.height
            )
            
            // Check if this belongs to an existing cluster
            // We look for a cluster that is "close"
            var added = false
            for i in 0..<clusters.count {
                let cluster = clusters[i]
                
                // Heuristic: if close vertically and horizontally
                // Vision coords are normalized 0-1.
                // Reduced thresholds to prevent merging distinct bubbles too aggressively
                // Stricter thresholds to separate intertwined bubbles
                let verticalThreshold: CGFloat = 0.01 // 1% of page height
                let horizontalThreshold: CGFloat = 0.015 // 1.5% of page width
                
                // Check overlap or proximity
                let intersectsOrClose = cluster.boundingBox.insetBy(dx: -horizontalThreshold, dy: -verticalThreshold).intersects(box)
                
                if intersectsOrClose {
                    // Merge
                    let newBox = cluster.boundingBox.union(box)
                    let newText = cluster.text + " " + text
                    var newRects = cluster.rects
                    newRects.append(visionBox) // Keep original Vision rects for debugging/fallback rendering if needed
                    
                    clusters[i] = TextCluster(boundingBox: newBox, text: newText, rects: newRects)
                    added = true
                    break
                }
            }
            
            if !added {
                clusters.append(TextCluster(boundingBox: box, text: text, rects: [visionBox]))
            }
        }
        
        return clusters
    }
    
    private func cleanOCRText(_ text: String) -> String {
        var cleaned = text
        
        // Common OCR fixups
        let replacements: [(String, String)] = [
            ("|", "I"),
            ("  ", " ")
        ]
        
        for (bad, good) in replacements {
            cleaned = cleaned.replacingOccurrences(of: bad, with: good)
        }
        
        return cleaned
    }

    func cleanFilename(from url: URL) -> String {
        var name = url.deletingPathExtension().lastPathComponent
        if name.lowercased().hasPrefix("reading_") {
            name = String(name.dropFirst("reading_".count))
        }
        return name
    }
}

// ... (Structs) ...



struct TextCluster: Identifiable {
    let id = UUID()
    let boundingBox: CGRect
    let text: String
    let rects: [CGRect]
    var bubblePath: Path? = nil // NEW
}

struct TranslatedOverlay: Identifiable {
    let id: UUID
    let text: String
    let fontStyle: String // NEW
    let boundingBox: CGRect
    let rects: [CGRect]
    var path: Path? = nil
    
    // Clean properties
    var cleanText: String {
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))
    }
}

struct ReaderPageView: View {
    // Use ComicReaderView.TranslationMode directly
    
    let imageURL: URL
    let translationMode: ComicReaderView.TranslationMode // Changed from viewMode
    let overlays: [TranslatedOverlay]
    let candidates: [TextCluster]
    @Binding var selectedIndices: Set<Int>
    @State private var overlayOffsets: [UUID: CGSize] = [:] // Track drag offsets
    let rawObservations: [CGRect]
    let filteredRects: [CGRect]
    let bubbleRects: [CGRect]

    let showDebug: Bool
    let showDebugLog: Bool // Needed for ReaderOverlayView
    let visionBalloons: [TranslatedBalloon] // NEW
    
    var body: some View {
        GeometryReader { geometry in
            if let image = UIImage(contentsOfFile: imageURL.path) {
                ZoomableScrollView {
                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: geometry.size.width, height: geometry.size.height)

                    
                    // (Tap gesture moved to end)
                    
                    // Transparent layer to catch taps everywhere - MOVED BEHIND CANDIDATES
                    // This allows buttons (which are in Candidates layer) to receive taps first
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .onTapGesture { location in
                            handleTap(at: location, geometry: geometry, imageSize: image.size)
                        }
                    
                    // Draw Debug Info
                    if showDebug {
                        // Raw (Red)
                        ForEach(0..<rawObservations.count, id: \.self) { i in
                            let rect = convertVisionRect(rawObservations[i], in: geometry.size, imageSize: image.size)
                            Rectangle()
                                .stroke(Color.red, lineWidth: 1)
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                        }
                        
                        // Filtered (Blue)
                        ForEach(0..<filteredRects.count, id: \.self) { i in
                            let rect = convertVisionRect(filteredRects[i], in: geometry.size, imageSize: image.size)
                            Rectangle()
                                .stroke(Color.blue, lineWidth: 2) // Thicker
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                        }
                        
                        // Bubbles (Green)
                        ForEach(0..<bubbleRects.count, id: \.self) { i in
                            let rect = convertVisionRect(bubbleRects[i], in: geometry.size, imageSize: image.size)
                            Rectangle()
                                .stroke(Color.green, lineWidth: 3)
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                        }
                    }
                    
                    // Draw Candidates (Buttons on top)
                    if !candidates.isEmpty {
                        ForEach(0..<candidates.count, id: \.self) { index in
                            let candidate = candidates[index]
                            let isSelected = selectedIndices.contains(index)
                            
                            // If we have a path, draw it!
                            if let path = candidate.bubblePath {
                                ScaledPath(path: path, viewSize: geometry.size, imageSize: image.size)
                                    .stroke(isSelected ? Color.green : Color.blue, lineWidth: 2)
                                    .opacity(0.7)
                            } else {
                                // Fallback to rect
                                let rect = convertVisionRect(candidate.boundingBox, in: geometry.size, imageSize: image.size)
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.blue, lineWidth: 1)
                                    .frame(width: rect.width, height: rect.height)
                                    .position(x: rect.midX, y: rect.midY)
                            }
                            
                            // MODE: Source Text (Show OCR text below selected bubbles)
                            if translationMode == .sourceText && isSelected {
                                let rect = convertVisionRect(candidate.boundingBox, in: geometry.size, imageSize: image.size)
                                
                                Text(candidate.text)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.black)
                                    .multilineTextAlignment(.center)
                                    .padding(8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.white)
                                            .shadow(radius: 2)
                                    )
                                    .frame(width: max(100, rect.width * 1.5))
                                    .position(x: rect.midX, y: rect.maxY + 40) // Below bubble
                            }
                            
                            // Selection Button (Always visible on top of candidate)
                            let buttonRect = candidate.bubblePath != nil 
                                ? ScaledPath(path: candidate.bubblePath!, viewSize: geometry.size, imageSize: image.size)
                                    .path(in: CGRect(origin: .zero, size: geometry.size))
                                    .boundingRect
                                : convertVisionRect(candidate.boundingBox, in: geometry.size, imageSize: image.size)
                            
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 30))
                                .foregroundColor(isSelected ? .green : .blue)
                                .background(Circle().fill(Color.white))
                                .position(x: buttonRect.maxX, y: buttonRect.minY) // Top-right corner
                                .onTapGesture {
                                    if isSelected {
                                        selectedIndices.remove(index)
                                    } else {
                                        selectedIndices.insert(index)
                                    }
                                }
                        }
                    }
                    
                    // MODE: Translated Overlay OR Source Text (Gemini)
                    if translationMode == .translatedOverlay || translationMode == .sourceText {
                        
                        // NEW: Gemini Vision Overlays
                        if !visionBalloons.isEmpty {
                            ReaderOverlayView(
                                imageSize: image.size,
                                balloons: visionBalloons,
                                showDebugShapes: showDebugLog
                            )
                        }
                        
                        // Legacy: Translated Overlays (Manual Selection)
                        if !overlays.isEmpty {
                            // 1. Draw Backgrounds (Bottom Layer)
                            ForEach(overlays, id: \.id) { overlay in
                                if let path = overlay.path {
                                    ScaledPath(path: path, viewSize: geometry.size, imageSize: image.size)
                                        .fill(Color.white)
                                        .shadow(radius: 2)
                                } else {
                                    let mainRect = convertVisionRect(overlay.boundingBox, in: geometry.size, imageSize: image.size)
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.white)
                                        .frame(width: mainRect.width, height: mainRect.height)
                                        .position(x: mainRect.midX, y: mainRect.midY)
                                }
                            }
                            
                            // 2. Draw Text (Top Layer)
                            ForEach(overlays) { overlay in
                                if let globalPath = overlay.path {
                                    let scaledPath = ScaledPath(path: globalPath, viewSize: geometry.size, imageSize: image.size)
                                    let pathInView = scaledPath.path(in: CGRect(origin: .zero, size: geometry.size))
                                    let boundingRect = pathInView.boundingRect
                                    let localPath = pathInView.offsetBy(dx: -boundingRect.minX, dy: -boundingRect.minY)
                                    
                                    BubbleTextView(
                                        text: overlay.cleanText,
                                        path: localPath,
                                        fontStyle: overlay.fontStyle,
                                        color: .black
                                    )
                                    .frame(width: boundingRect.width, height: boundingRect.height)
                                    .position(x: boundingRect.midX, y: boundingRect.midY)
                                    
                                } else {
                                    let safeRect = convertVisionRect(overlay.boundingBox, in: geometry.size, imageSize: image.size)
                                    BubbleTextView(
                                        text: overlay.cleanText,
                                        path: Path(safeRect.offsetBy(dx: -safeRect.minX, dy: -safeRect.minY)),
                                        fontStyle: overlay.fontStyle,
                                        color: .black
                                    )
                                    .frame(width: safeRect.width, height: safeRect.height)
                                    .position(x: safeRect.midX, y: safeRect.midY)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

    
    // --- HELPER METHODS ---
    
    func getFont(for style: String) -> Font {
        switch style {
        case "shout": return .custom("Impact", size: 16) // Aggressive
        case "computer": return .custom("CourierNewPS-BoldMT", size: 14) // Robotic
        case "italic": return .custom("ChalkboardSE-Bold", size: 14).italic() // Whisper/Thought
        case "handwritten": return .custom("Noteworthy-Bold", size: 14) // Alternate style
        default: return .custom("ChalkboardSE-Bold", size: 14) // Standard
        }
    }
    
    // Iterative shrinking algorithm to find largest rect strictly inside the path
    func findLargestSafeRect(for overlay: TranslatedOverlay, geometry: GeometryProxy, imageSize: CGSize) -> CGRect {
        // 1. Get initial bounding rect (Vision or Path bounds)
        var rect: CGRect
        var bubblePath: Path? = nil
        
        if let path = overlay.path {
            let scaledPath = ScaledPath(path: path, viewSize: geometry.size, imageSize: imageSize)
            let pathInView = scaledPath.path(in: CGRect(origin: .zero, size: geometry.size))
            rect = pathInView.boundingRect
            bubblePath = pathInView
        } else {
            rect = convertVisionRect(overlay.boundingBox, in: geometry.size, imageSize: imageSize)
        }
        
        guard let path = bubblePath else {
            // If no path (just rect), use 90% unsafe scale
            return rect.insetBy(dx: rect.width * 0.05, dy: rect.height * 0.05)
        }
        
        // 2. Iterative Inset Check
        // Try to fit the rect. If corners are out, inset.
        var bestRect = rect
        let maxIterations = 20
        let insetStep = min(rect.width, rect.height) * 0.02 // 2% step
        
        for _ in 0..<maxIterations {
            let p1 = CGPoint(x: bestRect.minX, y: bestRect.minY)
            let p2 = CGPoint(x: bestRect.maxX, y: bestRect.minY)
            let p3 = CGPoint(x: bestRect.maxX, y: bestRect.maxY)
            let p4 = CGPoint(x: bestRect.minX, y: bestRect.maxY)
            
            // Check all 4 corners + midpoints for better safety
            let points = [p1, p2, p3, p4]
            let allInside = points.allSatisfy { path.contains($0) }
            
            if allInside {
                // Found it! Return this rect.
                // Optional: Inset one more time for padding
                return bestRect.insetBy(dx: 2, dy: 2)
            }
            
            // Shrink
            bestRect = bestRect.insetBy(dx: insetStep, dy: insetStep)
        }
        
        // Fallback: Return deeply inset rect (safe bet)
        return rect.insetBy(dx: rect.width * 0.25, dy: rect.height * 0.25)
    }

    // Legacy Helper (keep for now if needed by other parts, though unused in loop)
    func getTextRect(for overlay: TranslatedOverlay, geometry: GeometryProxy, imageSize: CGSize) -> CGRect {
        if let path = overlay.path {
            let scaledPath = ScaledPath(path: path, viewSize: geometry.size, imageSize: imageSize)
            let pathInView = scaledPath.path(in: CGRect(origin: .zero, size: geometry.size))
            return pathInView.boundingRect
        } else {
            return convertVisionRect(overlay.boundingBox, in: geometry.size, imageSize: imageSize)
        }
    }
    
    private func handleTap(at location: CGPoint, geometry: GeometryProxy, imageSize: CGSize) {
        // Check which candidate contains the tap
        for (index, candidate) in candidates.enumerated() {
            let rect = convertVisionRect(candidate.boundingBox, in: geometry.size, imageSize: imageSize)
            // Inflate touch area slightly for easier tapping
            let touchRect = rect.insetBy(dx: -10, dy: -10)
            
            if touchRect.contains(location) {
                if selectedIndices.contains(index) {
                    selectedIndices.remove(index)
                } else {
                    selectedIndices.insert(index)
                }
            }
        }
    }
    
    // Helper to convert Vision coordinates (0,0 bottom-left) to SwiftUI (0,0 top-left)
    // Also handles aspect fit scaling
    func convertVisionRect(_ visionRect: CGRect, in viewSize: CGSize, imageSize: CGSize) -> CGRect {
        // Calculate the actual frame of the image within the aspect fit view
        let imageAspectRatio = imageSize.width / imageSize.height
        let viewAspectRatio = viewSize.width / viewSize.height
        
        var renderRect = CGRect.zero
        
        if imageAspectRatio > viewAspectRatio {
            // Image is wider than view, fits width
            let scale = viewSize.width / imageSize.width
            let renderHeight = imageSize.height * scale
            let yOffset = (viewSize.height - renderHeight) / 2
            renderRect = CGRect(x: 0, y: yOffset, width: viewSize.width, height: renderHeight)
        } else {
            // Image is taller than view, fits height
            let scale = viewSize.height / imageSize.height
            let renderWidth = imageSize.width * scale
            let xOffset = (viewSize.width - renderWidth) / 2
            renderRect = CGRect(x: xOffset, y: 0, width: renderWidth, height: viewSize.height)
        }
        
        // Vision Y is flipped
        let x = renderRect.minX + (visionRect.minX * renderRect.width)
        // Vision y=0 is bottom, y=1 is top. SwiftUI y=0 is top.
        // So visionY=0 -> renderRect.maxY. visionY=1 -> renderRect.minY
        let y = renderRect.maxY - (visionRect.maxY * renderRect.height)
        
        let width = visionRect.width * renderRect.width
        let height = visionRect.height * renderRect.height
        
        return CGRect(x: x, y: y, width: width, height: height)
    }


}

// Helper to scale the normalized path to view coordinates
struct ScaledPath: Shape {
    let path: Path
    let viewSize: CGSize
    let imageSize: CGSize
    
    func path(in rect: CGRect) -> Path {
        // Calculate scale and offset to match AspectFit
        let imageAspectRatio = imageSize.width / imageSize.height
        let viewAspectRatio = viewSize.width / viewSize.height
        
        var renderRect = CGRect.zero
        
        if imageAspectRatio > viewAspectRatio {
            let scale = viewSize.width / imageSize.width
            let renderHeight = imageSize.height * scale
            let yOffset = (viewSize.height - renderHeight) / 2
            renderRect = CGRect(x: 0, y: yOffset, width: viewSize.width, height: renderHeight)
        } else {
            let scale = viewSize.height / imageSize.height
            let renderWidth = imageSize.width * scale
            let xOffset = (viewSize.width - renderWidth) / 2
            renderRect = CGRect(x: xOffset, y: 0, width: renderWidth, height: viewSize.height)
        }
        
        // Transform: Scale by renderRect size, Translate by renderRect origin
        let transform = CGAffineTransform(scaleX: renderRect.width, y: renderRect.height)
            .concatenating(CGAffineTransform(translationX: renderRect.minX, y: renderRect.minY))
        
        return path.applying(transform)
    }
}

struct BubbleShape: Shape {
    let rects: [CGRect]
    let imageSize: CGSize
    let viewSize: CGSize
    let inflation: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Calculate scale and offset to match AspectFit
        let imageAspectRatio = imageSize.width / imageSize.height
        let viewAspectRatio = viewSize.width / viewSize.height
        
        var renderRect = CGRect.zero
        
        if imageAspectRatio > viewAspectRatio {
            let scale = viewSize.width / imageSize.width
            let renderHeight = imageSize.height * scale
            let yOffset = (viewSize.height - renderHeight) / 2
            renderRect = CGRect(x: 0, y: yOffset, width: viewSize.width, height: renderHeight)
        } else {
            let scale = viewSize.height / imageSize.height
            let renderWidth = imageSize.width * scale
            let xOffset = (viewSize.width - renderWidth) / 2
            renderRect = CGRect(x: xOffset, y: 0, width: renderWidth, height: viewSize.height)
        }
        
        for visionRect in rects {
            // Vision Y is flipped
            let x = renderRect.minX + (visionRect.minX * renderRect.width)
            let y = renderRect.maxY - (visionRect.maxY * renderRect.height)
            let w = visionRect.width * renderRect.width
            let h = visionRect.height * renderRect.height
            
            let r = CGRect(x: x, y: y, width: w, height: h).insetBy(dx: -inflation, dy: -inflation)
            path.addRoundedRect(in: r, cornerSize: CGSize(width: 10, height: 10))
        }
        
        return path
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
