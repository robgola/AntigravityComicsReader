import SwiftUI

struct PendingDownloadItem: Identifiable {
    let id = UUID()
    let bookId: String
    let bookName: String
    let targetFolder: String
}

struct SeriesListView: View {
    let library: Library
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    @State private var seriesList: [Series] = []
    @State private var rootFolder: FolderNode?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var useFolderView = true // Toggle state
    @State private var hasEffectiveFolders = false // If false, hide toggle
    
    // Batch Download State
    @State private var showSeriesDownloadAlert = false
    @State private var selectedSeriesForDownload: Series?
    
    @State private var showFolderDownloadAlert = false
    @State private var selectedFolderForDownload: FolderNode?
    @State private var selectedFolderPath: String = "" // Added for path tracking
    @State private var folderDownloadCount = 0 // Est. number of series
    
    // Conflict Management
    @State private var pendingConflicts: [PendingDownloadItem] = []
    @State private var showConflictAlert = false
    
    // 5 Columns Grid
    let columns = Array(repeating: GridItem(.flexible(), spacing: 20), count: 5)
    
    // Cache for series covers
    @State private var seriesCovers: [String: UIImage] = [:]

    var body: some View {
        ZStack {
            // Global Background: Random Blurred Cover
            // FIX: Use GeometryReader or strict framing to prevent expansion
            GeometryReader { geo in
                Group {
                    if let randomCover = seriesCovers.values.randomElement() {
                        Image(uiImage: randomCover)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .blur(radius: 15)
                            .opacity(0.4)
                    } else {
                        Color(white: 0.15)
                    }
                }
            }
            .ignoresSafeArea(edges: [.bottom, .horizontal])
            Color.black.opacity(0.3).ignoresSafeArea(edges: [.bottom, .horizontal]) // Contrast layer
            
            if isLoading {
                ProgressView("Loading series...")
                    .colorScheme(.dark)
            } else if errorMessage != nil {
// ...
            } else {
                // VStack Layout for Zones
                VStack(spacing: 0) {
                    // Zone 2: Breadcrumb Header (Server > Library)
                    ZStack {
                        // Background Element for Zone 2
                        Rectangle()
                            .fill(Color.black.opacity(0.4))
                            .overlay(Rectangle().frame(height: 1).foregroundColor(Color.white.opacity(0.1)), alignment: .bottom)
                            .ignoresSafeArea(edges: .top) // Should it? No, Menu is above.
                        
                        HStack {
                            // Back Button (Zone 2 Left)
                            Button(action: { dismiss() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                    Text("Libraries")
                                }
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(8)
                            }
                            
                            Spacer()
                            
                            // Toggles
                            if hasEffectiveFolders {
                                Button(action: { useFolderView.toggle() }) {
                                    Image(systemName: useFolderView ? "folder.fill" : "list.bullet")
                                        .foregroundColor(.white)
                                        .padding(8)
                                        .background(Color.white.opacity(0.1))
                                        .cornerRadius(8)
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        
                         // Centered Title (Server > Library)
                        VStack(spacing: 2) {
                            Text("\(appState.serverName)  ›  \(library.name)")
                                .font(.headline)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                        }
                        .allowsHitTesting(false) // Let touches pass to buttons
                    }
                    .frame(height: 60) // Fixed height for elegance
                    
// ...
                    // Zone 3: Content (Series List)
                    ScrollView {
                        if useFolderView && hasEffectiveFolders, let root = rootFolder {
                            FolderContentView(
                                node: root,
                                libraryName: library.name,
                                currentPath: "", // Root has empty relative path
                                columns: columns,
                                seriesCovers: $seriesCovers,
                                onDownloadFolder: { node, path in
                                    self.selectedFolderForDownload = node
                                    self.selectedFolderPath = path
                                    self.folderDownloadCount = FolderUtilities.countSeriesRecursive(node: node)
                                    self.showFolderDownloadAlert = true
                                },
                                onDownloadSeries: { series, path in
                                    self.selectedSeriesForDownload = series
                                    self.selectedFolderPath = path 
                                    self.showSeriesDownloadAlert = true
                                }
                            )
                        } else {
                            // Flat List
                            LazyVGrid(columns: columns, spacing: 40) {
                                ForEach(seriesList) { series in
                                    NavigationLink(destination: BookListView(series: series, libraryName: library.name)) {
                                         SeriesCard(series: series, cover: seriesCovers[series.id])
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .highPriorityGesture(LongPressGesture().onEnded { _ in
                                        self.selectedSeriesForDownload = series
                                        self.showSeriesDownloadAlert = true
                                    })
                                }
                            }
                            .padding()
                        }
                        
                        // Bottom Padding
                        Spacer().frame(height: 40)
                    }
                }
                // Removed top padding
            }
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: Series.self) { series in
            BookListView(series: series, libraryName: library.name)
        }
        // ALERTS
        .alert("Download Series?", isPresented: $showSeriesDownloadAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Download") {
                if let s = selectedSeriesForDownload {
                    downloadSeries(s, relativePath: selectedFolderPath)
                }
            }
        } message: {
            if let s = selectedSeriesForDownload {
                Text("Do you want to download \"\(s.name)\" (\(s.booksCount) books)?")
            } else {
                Text("Download selection?")
            }
        }
        .alert("Download Folder?", isPresented: $showFolderDownloadAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Download All") {
                if let f = selectedFolderForDownload {
                    downloadFolder(f, at: selectedFolderPath)
                }
            }
        } message: {
            if let f = selectedFolderForDownload {
                Text("Do you want to download \"\(f.name)\" / \(folderDownloadCount) Series?")
            } else {
                Text("Download this folder?")
            }
        }
        // Conflict Alert
        .alert("File Exists", isPresented: $showConflictAlert) {
            Button("No (Skip)", role: .cancel) {
                if !pendingConflicts.isEmpty { pendingConflicts.removeFirst() }
                checkNextConflict()
            }
            if pendingConflicts.count > 1 {
                Button("Yes to All") {
                    confirmAllConflicts()
                }
            }
            Button("Yes (Overwrite)") {
                confirmFirstConflict()
            }
        } message: {
            if let item = pendingConflicts.first {
                Text("File \"\(item.bookName)\" already exists. Overwrite?")
            } else {
                Text("File exists. Overwrite?")
            }
        }
        .task(id: library.id) {
             if seriesList.isEmpty {
                 // Clean up potential layout shift
                 try? await Task.sleep(nanoseconds: 100_000_000)
                 loadSeries()
             }
         }
    } // End of body
    
    // MARK: - Batch Download Logic
    
    private func downloadSeries(_ series: Series, relativePath: String = "") {
        Task {
            print("🚀 Starting Batch Download for Series: \(series.name)")
            do {
                // Fetch ALL books
                let books = try await KomgaService.shared.fetchBooks(for: series.id)
                
                // Determine Target Folder
                var targetFolder = library.name
                if !relativePath.isEmpty {
                    targetFolder += "/" + relativePath
                }
                
                let isRedundantName = relativePath.hasSuffix(series.name)
                // If it's a One Shot (1 book) OR the name is redundant (Folder == Series), don't append Series Name
                let isOneShot = books.count == 1 
                
                if !isOneShot && !isRedundantName {
                    targetFolder += "/" + series.name
                }
                
                // Check conflicts and Queue
                var conflicts: [PendingDownloadItem] = []
                
                for book in books {
                    // Check existence
                    // We must replicate the exact path logic of DownloadManager/KomgaService
                    // KomgaService uses 'targetFolder' and 'bookName'.
                    let exists = KomgaService.shared.isFilePresent(bookName: book.name, inFolder: targetFolder)
                    
                    if exists {
                        conflicts.append(PendingDownloadItem(bookId: book.id, bookName: book.name, targetFolder: targetFolder))
                    } else {
                        // Safe to download
                        await MainActor.run {
                            DownloadManager.shared.addToQueue(
                                bookId: book.id,
                                bookName: book.name,
                                targetFolder: targetFolder
                            )
                        }
                    }
                }
                
                // Handle Conflicts
                if !conflicts.isEmpty {
                    await MainActor.run {
                        self.pendingConflicts.append(contentsOf: conflicts)
                        if !self.showConflictAlert {
                             self.showConflictAlert = true
                        }
                    }
                }
                
                print("✅ Queued \(books.count - conflicts.count) books. Conflicts: \(conflicts.count)")
            } catch {
                print("❌ Download Error: \(error)")
            }
        }
    }
    
    private func downloadFolder(_ node: FolderNode, at path: String) {
        let parentPath = (path as NSString).deletingLastPathComponent
        let safeParent = parentPath == "/" ? "" : parentPath
        
        let items = FolderUtilities.collectSeriesForDownload(node: node, parentPath: safeParent)
        
        for item in items {
             downloadSeries(item.series, relativePath: item.relativePath)
        }
    }
    
    // MARK: - Conflict Helpers
    private func checkNextConflict() {
        if !pendingConflicts.isEmpty {
            // Small delay to allow alert to cycle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.showConflictAlert = true
            }
        }
    }
    
    private func confirmFirstConflict() {
        guard let item = pendingConflicts.first else { return }
        DownloadManager.shared.addToQueue(bookId: item.bookId, bookName: item.bookName, targetFolder: item.targetFolder)
        pendingConflicts.removeFirst()
        checkNextConflict()
    }
    
    private func confirmAllConflicts() {
        for item in pendingConflicts {
            DownloadManager.shared.addToQueue(bookId: item.bookId, bookName: item.bookName, targetFolder: item.targetFolder)
        }
        pendingConflicts.removeAll()
    } 

    private func loadSeries() {
        isLoading = true
        errorMessage = nil
        
        Task {
            await MainActor.run { isLoading = true }
             
            do {
                let list = try await KomgaService.shared.fetchSeries(for: library.id)
                // Sort Alphabetically by Name
                self.seriesList = list.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
                
                // Fetch Books for Path Mapping (this might take a moment)
                // We use a separate Task or wait? Let's await to ensure tree is built.
                // NOTE: This fetches ALL books (up to 2000).
                let allBooks = try await KomgaService.shared.fetchAllBooks(for: library.id)
                
                // Create SeriesID -> Path map
                var pathMap: [String: String] = [:]
                for book in allBooks {
                    // Only need one book per series to get the path
                    if pathMap[book.seriesId] == nil {
                        pathMap[book.seriesId] = book.url
                    }
                }
                
                // Check if we have effective folders (based on the map now)
                let hasPaths = !pathMap.isEmpty
                
                // Build Tree
                // roots is now [FolderNode], but it contains a single "virtual_root"
                let roots = FolderUtilities.buildTree(from: list, pathMap: pathMap)
                
                await MainActor.run {
                    self.seriesList = list // Update list again just in case
                    if let combinedRoot = roots.first {
                        self.rootFolder = combinedRoot
                    } else {
                        // Fallback
                        self.rootFolder = FolderNode(id: "virtual_root", name: "Root", children: [], series: list)
                    }
                    self.hasEffectiveFolders = hasPaths
                    if !hasPaths {
                        self.useFolderView = false // Force list view
                    }
                    self.isLoading = false
                }

                // Fetch random covers for visible items
                await fetchCovers(for: list)
                
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    private func fetchCovers(for list: [Series]) async {
        // Simple async loop
         for s in list {
            if seriesCovers[s.id] == nil {
                if let img = await KomgaService.shared.fetchRandomBookThumbnail(forSeries: s.id) {
                    await MainActor.run {
                        seriesCovers[s.id] = img
                    }
                }
            }
        }
    }
}

// Subview for Recursive Folder Display
struct FolderContentView: View {
    let node: FolderNode
    let libraryName: String
    let currentPath: String // Path relative to Library Root
    let columns: [GridItem]
    @Binding var seriesCovers: [String: UIImage]
    
    // Callbacks for Actions
    var onDownloadFolder: ((FolderNode, String) -> Void)? // Pass path too
    var onDownloadSeries: ((Series, String) -> Void)? // Changed signature to include path
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 40) {
            // Folders first
            ForEach(node.children) { child in
                let childPath = currentPath.isEmpty ? child.name : "\(currentPath)/\(child.name)"
                NavigationLink(destination: FolderDetailView(node: child, libraryName: libraryName, currentPath: childPath, columns: columns, seriesCovers: $seriesCovers)) {
                    FolderCard(node: child, seriesCovers: seriesCovers)
                }
                .buttonStyle(PlainButtonStyle())
                .highPriorityGesture(LongPressGesture().onEnded { _ in
                    onDownloadFolder?(child, childPath)
                })
            }
            
            // Then Series
            ForEach(node.series) { series in
                NavigationLink(destination: BookListView(series: series, libraryName: libraryName)) {
                    SeriesCard(series: series, cover: seriesCovers[series.id])
                }
                .buttonStyle(PlainButtonStyle())
                .highPriorityGesture(LongPressGesture().onEnded { _ in
                    // Fix: Pass empty path to flatten the download (ignore folder structure)
                    // User Request: "1998 Gen 13" instead of "Gen 13/1998 Gen 13"
                    onDownloadSeries?(series, "")
                })
            }
        }
        .padding()
    }
}

// Detail View for a Folder
struct FolderDetailView: View {
    let node: FolderNode
    let libraryName: String
    let currentPath: String
    let columns: [GridItem]
    @Binding var seriesCovers: [String: UIImage]
    @Environment(\.dismiss) var dismiss
    
    // Local Alert State
    @State private var showFolderDownloadAlert = false
    @State private var showSeriesDownloadAlert = false
    @State private var selectedSeriesForDownload: Series?
    @State private var selectedFolderForDownload: FolderNode? // Missing
    @State private var selectedFolderPath: String = "" // Missing
    @State private var folderDownloadCount = 0
    
    var body: some View {
        ZStack {
            // Global Background: Random Blurred Cover
            GeometryReader { geo in
                Group {
                    if let randomCover = seriesCovers.values.randomElement() {
                        Image(uiImage: randomCover)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .blur(radius: 15) // Reduced blur
                            .opacity(0.4)
                    } else {
                        Color(white: 0.15)
                    }
                }
            }
            .ignoresSafeArea(edges: [.bottom, .horizontal])
            Color.black.opacity(0.3).ignoresSafeArea() // Contrast layer
            
            VStack(spacing: 0) {
                // Header
                ZStack {
                    Text(node.name)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "chevron.left")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                        Spacer()
                        
                        // Main Download Button for CURRENT Folder
                        Button(action: {
                            self.selectedFolderPath = currentPath // Fix: Explicitly set path state
                            self.folderDownloadCount = FolderUtilities.countSeriesRecursive(node: node)
                            self.showFolderDownloadAlert = true
                        }) {
                            Image(systemName: "arrow.down.circle")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding()
                .background(Color.white.opacity(0.1)) // Glassy Header
                
                ScrollView {
                    FolderContentView(
                        node: node,
                        libraryName: libraryName,
                        currentPath: currentPath,
                        columns: columns,
                        seriesCovers: $seriesCovers,
                        onDownloadFolder: { folder, path in
                             // When downloading a sub-folder from here
                             self.folderDownloadCount = FolderUtilities.countSeriesRecursive(node: folder)
                             // Since we don't have a specific state for "SelectedFolder with Path", 
                             // We will just assume 'downloadFolder' method below takes (Folder, Path).
                             // Ideally we store 'selectedFolderNode' and 'selectedFolderPath'.
                             // But adding more state variables is annoying. 
                             // Let's just launch the download directly?
                             // User wants Alert.
                             // OK, we must store the tuple or just the node and reconstruct path?
                             // We have the path in callback.
                             // Let's create a temporary struct or just use a state for the path.
                             // Quick fix: define state for `selectedFolderPath`.
                             self.selectedFolderForDownload = folder
                             self.selectedFolderPath = path
                             self.showFolderDownloadAlert = true
                        },
                        onDownloadSeries: { series, path in
                             self.selectedSeriesForDownload = series
                             self.selectedFolderPath = path
                             self.showSeriesDownloadAlert = true
                        }
                    )
                    .padding(.top)
                }
            }
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        // ALERTS
        .alert("Download Folder?", isPresented: $showFolderDownloadAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Download All") {
                if let f = selectedFolderForDownload {
                    downloadFolder(f, at: selectedFolderPath)
                } else {
                    // Fallback to current node if none selected (e.g. invalid state, default to self)
                    downloadFolder(node, at: currentPath)
                }
            }
        } message: {
            // Debug State
            let _ = print("🔍 [Alert] Folder Path State: '\(selectedFolderPath)'")
            if let f = selectedFolderForDownload {
                Text("Do you want to download \"\(f.name)\" / \(folderDownloadCount) Series?")
            } else {
                Text("Do you want to download \"\(node.name)\" / \(folderDownloadCount) Series?")
            }
        }
        .alert("Download Series?", isPresented: $showSeriesDownloadAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Download") {
                if let s = selectedSeriesForDownload {
                    downloadSeries(s, relativePath: selectedFolderPath)
                }
            }
        } message: {
            if let s = selectedSeriesForDownload {
                // Debug State
                let _ = print("🔍 [Alert] Series Path State: '\(selectedFolderPath)'")
                Text("Do you want to download \"\(s.name)\" (\(s.booksCount) books)?")
            }
        }
    }
    
    private func downloadSeries(_ series: Series, relativePath: String) {
        // Target Logic:
        // 1. Base is LibraryName + RelativePath
        var basePath = libraryName
        if !relativePath.isEmpty {
            basePath += "/" + relativePath
        }
        
        // 2. Determine if we need a Series folder
        // Rule A (User Request): If it's a "One Shot" (1 Book), put it directly in the folder.
        // Rule B (Optimization): If the folder name matches the series name (e.g. "Paperino/Paperino"), flatten it.
        
        var targetPath = basePath
        let isRedundantName = relativePath.hasSuffix(series.name)
        let isOneShot = series.booksCount == 1
        
        if isOneShot {
            // Flatten: Put book directly in basePath
            // targetPath remains basePath
        } else {
            // Multi-Book Series
            if !isRedundantName {
                targetPath += "/" + series.name
            }
        }
        
        print("⬇️ [Download] Series '\(series.name)' -> '\(targetPath)'")
        
        Task {
            let books = try? await KomgaService.shared.fetchBooks(for: series.id)
            if let books = books {
                for book in books {
                    await MainActor.run {
                        DownloadManager.shared.addToQueue(
                            bookId: book.id,
                            bookName: book.name,
                            targetFolder: targetPath
                        )
                    }
                }
            }
        }
    }
    
    // Updated signature to match call site
    private func downloadFolder(_ node: FolderNode, at path: String) {
        // Calculate parent path for the helper
        let parentPath = (path as NSString).deletingLastPathComponent
        let safeParent = parentPath == "/" ? "" : parentPath
        
        // Fix: Use relative path from the selected node (empty parent)
        // This ensures if we download "Folder/Sub", we get "Sub" at root, not "Folder/Sub".
        let items = FolderUtilities.collectSeriesForDownload(node: node, parentPath: "")
        
        for item in items {
             // Pass the relative path (e.g. "Pippo/Paperino") to downloadSeries
             // downloadSeries will handle flattening and redundancy checks.
             downloadSeries(item.series, relativePath: item.relativePath)
        }
    }
}

// MARK: - Cluster View for Folders
struct FolderClusterView: View {
    let node: FolderNode
    var seriesCovers: [String: UIImage]
    
    // Compute 3 representative images
    private var collageImages: [UIImage] {
        var images: [UIImage] = []
        // Try getting covers from direct series
        for series in node.series.prefix(3) {
            if let img = seriesCovers[series.id] {
                images.append(img)
            }
        }
        // If not enough, try children
        if images.count < 3 {
             for child in node.children {
                 for series in child.series.prefix(3) {
                     if let img = seriesCovers[series.id], !images.contains(img) {
                         images.append(img)
                         if images.count >= 3 { break }
                     }
                 }
                 if images.count >= 3 { break }
             }
        }
        return images
    }
    
    var body: some View {
        ZStack {
            // Base Box Shadow/Shape (Wider)
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.2))
                .shadow(radius: 4)
                .frame(width: 120, height: 120) // Widened (was 100)
            
            // Render up to 3 covers in a scattered pile
            if collageImages.isEmpty {
                 Image(systemName: "folder.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 70) // Widened
                    .foregroundColor(.blue)
            } else {
                ForEach(Array(collageImages.prefix(3).enumerated()), id: \.offset) { index, img in
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 90, height: 110) // Widened (was 80)
                        .clipped()
                        .cornerRadius(4)
                        .shadow(radius: 2)
                        // Fan out logic - Adjusted for width
                        .rotationEffect(.degrees(Double(index - 1) * 8)) 
                        .offset(x: CGFloat(index - 1) * 12, y: CGFloat(index - 1) * 2)
                }
            }
            
            // Folder Icon Overlay Badge (Small)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Image(systemName: "folder.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                        .background(Color.white.clipShape(Circle()))
                        .padding(4)
                }
            }
            .frame(width: 120, height: 120) // Match new width
        }
    }
}

struct FolderCard: View {
    let node: FolderNode
    var seriesCovers: [String: UIImage]
    
    var body: some View {
        ZStack {
            // Card background (Uniform with SeriesCard)
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(white: 0.2))
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            
            VStack {
                // The Cluster Visualization
                FolderClusterView(node: node, seriesCovers: seriesCovers)
                    .frame(height: 140) // Adjusted height constraint
                
                // Name
                Text(Series.formatSeriesName(node.name))
                    .font(.caption)
                    .bold()
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .padding(.top, 4)
                
                // Subtitle: Series Count
                Text("\(node.series.count + node.children.reduce(0) { $0 + $1.series.count }) Series")
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .padding(.bottom, 4)
            }
            .padding(8)
        }
    }
}

struct SeriesCard: View {
    let series: Series
    let cover: UIImage?
    
    var body: some View {
        // Container for 3D effect
        ZStack {
            // Card background
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(white: 0.2))
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            
            VStack {
                // Reuse LibraryBoxView for Series (Directory Metaphor)
                LibraryBoxView(name: Series.formatSeriesName(series.name), coverImage: cover)
                
                // Count Badge
                Text("\(series.booksCount) books")
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .padding(.bottom, 4)
            }
            .padding(8)
        }
    }
}
