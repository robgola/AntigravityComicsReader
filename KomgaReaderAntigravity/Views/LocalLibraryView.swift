import SwiftUI

struct LocalLibraryView: View {
    let refreshTrigger: Bool
    @EnvironmentObject var appState: AppState // Persisted State
    @State private var showSettings = false
    
    // Deletion
    @State private var bookToDelete: LocalBook?
    @State private var showDeleteBookConfirmation = false
    @State private var folderToDelete: LocalFolderNode?
    @State private var showDeleteFolderConfirmation = false
    
    // Grid
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 15), count: 5)
    
    // Dashboard State
    @State private var selectedLibrary: String = "Tutte"
    @State private var focusedBook: LocalBook? // For "Preview" detail
    @State private var isContinueReadingExpanded = true
    @State private var isPreviewExpanded = true
    
    var body: some View {
        NavigationView {
            ZStack {
// ... (Background logic remains same)
                if appState.isScanningLocal {
                    ProgressView("Scansione libreria...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let root = appState.localRootNode, root.isEmpty {
// ... (Empty logic remains same)
                } else if let root = appState.localRootNode {
                    VStack(spacing: 0) {
                        // 1. Pill Filter Bar
                        PillFilterBar(tabs: appState.localLibraryTabs, selectedTab: $selectedLibrary)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 0.25, green: 0.22, blue: 0.20),
                                        Color(red: 0.15, green: 0.15, blue: 0.15)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                
                                // 2. Header Section
                                if selectedLibrary == "Tutte" {
                                    // "Continue Reading" Logic
                                    let allBooks = getAllBooks(from: root)
                                    let recentBooks = allBooks.filter { ReadingProgressManager.shared.hasProgress(for: $0.id) }
                                        .sorted { 
                                            let d1 = ReadingProgressManager.shared.getProgress(for: $0.id)?.lastReadDate ?? Date.distantPast
                                            let d2 = ReadingProgressManager.shared.getProgress(for: $1.id)?.lastReadDate ?? Date.distantPast
                                            return d1 > d2
                                        }
                                        .prefix(10).map { $0 }
                                    
                                    LibraryPreviewHeader(
                                        title: "Continue Reading...",
                                        books: recentBooks,
                                        isExpanded: $isContinueReadingExpanded,
                                        showToggle: true
                                    )
                                } else {
                                    // "Preview" Logic
                                    if let book = focusedBook {
                                        LibraryPreviewHeader(
                                            title: "Preview",
                                            books: [book],
                                            isExpanded: $isPreviewExpanded,
                                            showToggle: true
                                        )
                                    }
                                }
                                
                                // 3. Content Grid
                                let displayNode = getDisplayContent(root: root)
                                
                                if displayNode.children.isEmpty && displayNode.books.isEmpty {
                                    Text("No content found")
                                        .foregroundColor(.secondary)
                                        .padding()
                                } else {
                                    LocalFolderContentView(
                                        node: displayNode,
                                        columns: columns,
                                        onDelete: { book in
                                            self.bookToDelete = book
                                            self.showDeleteBookConfirmation = true
                                        },
                                        onSelect: selectedLibrary == "Tutte" ? nil : { book in
                                            // Tap to Select
                                            withAnimation {
                                                self.focusedBook = book
                                            }
                                        }
                                    )
                                }
                                
                                // Spacer for Overlay
                                Color.clear.frame(height: 60)
                            }
                        }
                    }
                }
            }
            .navigationBarHidden(true)

            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .task {
                // Optimized: Scan if empty OR if dirtied by new downloads
                if appState.localRootNode == nil || DownloadManager.shared.hasNewDownloads {
                    scanLocalLibrary()
                    DownloadManager.shared.hasNewDownloads = false
                } else {
                    // Update focus if needed (e.g. library switch)
                    updateFocusedBook()
                }
            }
            .onChange(of: refreshTrigger) { _, _ in
                scanLocalLibrary()
            }
            .onChange(of: selectedLibrary) { _, _ in
                updateFocusedBook()
            }
            // Alert 1: Delete Book
            .alert("Delete Comic?", isPresented: $showDeleteBookConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if let book = bookToDelete {
                        deleteBook(book)
                    }
                }
            } message: {
                if let book = bookToDelete {
                    Text("Are you sure you want to delete \"\(book.title)\"?")
                }
            }
            // Alert 2: Delete Folder (Recursive)
            .alert("Delete Folder?", isPresented: $showDeleteFolderConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete All", role: .destructive) {
                    if let folder = folderToDelete {
                        deleteFolder(folder)
                    }
                }
            } message: {
                if let folder = folderToDelete {
                    Text("Are you sure you want to delete the folder \"\(folder.name)\" and ALL \(folder.books.count + folder.children.count) items inside?\nThis cannot be undone.")
                }
            }
        }
        .navigationViewStyle(.stack)
    }
    
    // Logic to update focus on library change
    private func updateFocusedBook() {
        if selectedLibrary == "Tutte" {
            focusedBook = nil
            return
        }
        
        guard let root = appState.localRootNode else { return }
        
        // Find default book for current library
        if let libNode = root.children.first(where: { $0.name == selectedLibrary }) {
            // Priority: Direct Books
            if let first = libNode.books.first {
                focusedBook = first
                return
            }
            // Secondary: Subfolders
            focusedBook = findFirstBook(in: libNode.children)
        } else {
            focusedBook = nil
        }
    }
    
    private func findFirstBook(in nodes: [LocalFolderNode]) -> LocalBook? {
        for node in nodes {
            if let book = node.books.first { return book }
            if let nested = findFirstBook(in: node.children) { return nested }
        }
        return nil
    }

    private func getDisplayContent(root: LocalFolderNode) -> LocalFolderNode {
        if selectedLibrary == "Tutte" {
            // Merge content from all libraries
            var mergedChildren: [LocalFolderNode] = []
            var mergedBooks: [LocalBook] = []
            
            // 1. Root Books
            mergedBooks.append(contentsOf: root.books)
            
            // 2. Library Contents
            for library in root.children {
                mergedChildren.append(contentsOf: library.children)
                mergedBooks.append(contentsOf: library.books)
            }
            
            return LocalFolderNode(id: "virtual_root", name: "Tutte", children: mergedChildren, books: mergedBooks)
        } else {
            // Specific Library
            if let libNode = root.children.first(where: { $0.name == selectedLibrary }) {
                return libNode
            }
            return LocalFolderNode(id: "empty", name: "", children: [], books: [])
        }
    }
    
    private func getAllBooks(from node: LocalFolderNode) -> [LocalBook] {
        var books = node.books
        for child in node.children {
            books.append(contentsOf: getAllBooks(from: child))
        }
        return books
    }
    
    private func scanLocalLibrary() {
        appState.isScanningLocal = true
        Task {
            let libraryURL = KomgaService.shared.getLocalLibraryURL()
            let root = await LocalFolderUtilities.buildTree(from: libraryURL)
            // Identify library roots
            let roots = LocalFolderUtilities.scanLibraryRoots(from: libraryURL)
            
            await MainActor.run {
                appState.localRootNode = root
                appState.localLibraryTabs = roots // Dynamic tabs
                
                // Pick a random background cover
                if let randomCover = root.getRandomCovers(count: 1).first {
                    appState.localLibraryBackground = randomCover
                }
                
                if appState.localLibraryTabs.isEmpty {
                     // If no subfolders in Library, maybe we just have one implicit "Default" or just "Tutte"
                }
                appState.isScanningLocal = false
            }
        }
    }
    
    private func deleteBook(_ book: LocalBook) {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: book.originalURL)
        scanLocalLibrary()
    }
    
    private func deleteFolder(_ folder: LocalFolderNode) {
        let fileManager = FileManager.default
        try? fileManager.removeItem(atPath: folder.id)
        scanLocalLibrary()
    }
}

// LocalBook and LocalFolderNode moved to AppState.swift

struct LocalFolderUtilities {
    static func buildTree(from url: URL) async -> LocalFolderNode {
        let fileManager = FileManager.default
        let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .nameKey]
        
        // Scan current directory
        var children: [LocalFolderNode] = []
        var books: [LocalBook] = []
        
        guard let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: resourceKeys, options: [.skipsHiddenFiles]) else {
            return LocalFolderNode(id: url.path, name: url.lastPathComponent, children: [], books: [])
        }
        
        for itemURL in contents {
            let isDirectory = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            
            if isDirectory {
                // Recursively build child node
                let childNode = await buildTree(from: itemURL)
                if !childNode.isEmpty {
                    children.append(childNode)
                }
            } else {
                let ext = itemURL.pathExtension.lowercased()
                if ext == "cbz" || ext == "cbr" {
                    // It's a book
                    if let book = await loadBook(from: itemURL) {
                        books.append(book)
                    }
                }
            }
        }
        
        // Sort
        children.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        // User Request: Sort by Filename (using id which is filename) instead of Title
        books.sort { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        
        return LocalFolderNode(id: url.path, name: url.lastPathComponent, children: children, books: books)
    }
    
    static func loadBook(from fileURL: URL) async -> LocalBook? {
        // This simulates the previous 'scanForBooks' logic but for a single file
        // Helper to unzip and get cover using KomgaService or FileManager
        // Re-implement simplified version
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("reading_\(fileURL.lastPathComponent)")
        
        // Check cache/unzip (Simplified for brevity)
        var needsUnzip = true
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: tempDir.path, isDirectory: &isDir) && isDir.boolValue {
            if let c = try? fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil), !c.isEmpty {
                needsUnzip = false
            }
        }
        
        if needsUnzip {
            try? fileManager.removeItem(at: tempDir)
            try? KomgaService.shared.unzipBook(at: fileURL, to: tempDir)
        }
        
        // Get Cover
        var cover: UIImage?
        if let pages = try? fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            .filter({ ["jpg", "jpeg", "png", "webp"].contains($0.pathExtension.lowercased()) })
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }),
           let first = pages.first {
            cover = UIImage(contentsOfFile: first.path)
        }
        
        // Check for ComicInfo.xml
        var info: ComicInfo? = nil
        let comicInfoPath = tempDir.appendingPathComponent("ComicInfo.xml")
        
        // If we haven't unzipped yet (or if re-checking), extract just ComicInfo if possible?
        // For simple CBZ (Zip), we can just unzip everything.
        // Optimization: If file exists, parse it.
        if fileManager.fileExists(atPath: comicInfoPath.path) {
            if let data = try? Data(contentsOf: comicInfoPath) {
                info = ComicInfoParser.parse(data: data)
            }
        }
        
        return LocalBook(
            id: fileURL.deletingPathExtension().lastPathComponent,
            title: info?.title.isEmpty == false ? info!.title : fileURL.deletingPathExtension().lastPathComponent,
            originalURL: fileURL,
            url: tempDir,
            coverImage: cover,
            metadata: info
        )
    }
    // MARK: - Dashboard Helpers
    
    /// Scans the root ACR folder and returns top-level folder names (Libraries)
    static func scanLibraryRoots(from url: URL) -> [String] {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        
        return contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false }
            .map { $0.lastPathComponent }
            .sorted()
    }
}

// MARK: - Flattening Extensions/Helpers
extension LocalFolderNode {
    /// Recursively collects all series-level folders or promoted books
    /// For the "Tutte" (All) view, we likely want to show SERIES (Leaf Folders)
    /// A "Series" in file terms is a folder containing books (CBZ).
    /// EXCEPT if the structure is Library/Book.cbz (Single Book).
    
    func flattenToSeries() -> [LocalFolderNode] {
        var results: [LocalFolderNode] = []
        
        // If THIS node contains books, it is effectively a series (or a mixed folder).
        if !self.books.isEmpty {
            results.append(self)
        }
        
        // Also recurse
        for child in children {
            results.append(contentsOf: child.flattenToSeries())
        }
        
        // Deduplicate using ID (path) just in case
        // (Not strictly necessary if tree is clean, but safe)
        return results
    }
    
    /// Returns up to `count` random covers from this folder and subfolders
    func getRandomCovers(count: Int = 3) -> [UIImage] {
        var allCovers: [UIImage] = self.books.compactMap { $0.coverImage }
        
        // Simple recursion limit or breath-first to avoid infinite loop cost?
        // Just recursive for now.
        for child in children {
            allCovers.append(contentsOf: child.getRandomCovers(count: count)) // Recursion
            if allCovers.count > count * 3 { break } // Optimization: Stop if we have enough candidates
        }
        
        return Array(allCovers.shuffled().prefix(count))
    }
}

// MARK: - Views

// MARK: - Reusable Header Component
struct LibraryPreviewHeader: View {
    let title: String
    let books: [LocalBook]
    @Binding var isExpanded: Bool
    var showToggle: Bool = true
    
    @State private var activeSheetBook: LocalBook? = nil
    
    var body: some View {
        if !books.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(title)
                        .font(.title2)
                        .bold()
                        .foregroundColor(.white)
                    
                    if showToggle {
                        Button(action: {
                            withAnimation {
                                isExpanded.toggle()
                            }
                        }) {
                            Text(isExpanded ? "less" : "more")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                        }
                    }
                    
                    // "What's happened so far..." (Gemini) - Left Aligned
                    if let firstBook = books.first {
                        Button(action: {
                            activeSheetBook = firstBook
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                Text("Recap") // Shortened for space
                            }
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 10)
                            .background(
                                Capsule().fill(Color.blue.opacity(0.2))
                                    .overlay(Capsule().stroke(Color.blue.opacity(0.5), lineWidth: 1))
                            )
                        }
                    }
                    
                    Spacer()
                }
                .padding(.horizontal)
                // Removed dedicated block below
                
                if isExpanded {
                    ContinueReadingCarouselView(books: books)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical, 20)
            .background(
                LinearGradient(gradient: Gradient(colors: [Color(white: 0.10), Color(white: 0.05)]), startPoint: .top, endPoint: .bottom)
            )
            .sheet(item: $activeSheetBook) { book in
                // Prepare Data for Recap
                // Priority: ComicInfo > Filename Parsing
                
                let seriesName = book.metadata?.series ?? book.title // Fallback need improvement?
                let number = book.metadata?.number ?? "1"
                let volume = book.metadata?.volume ?? ""
                let publisher = book.metadata?.publisher ?? ""
                
                StoryRecapView(
                    series: seriesName.isEmpty ? book.title : seriesName,
                    number: number,
                    volume: volume,
                    publisher: publisher,
                    coverImage: book.coverImage
                )
                .presentationDetents([.medium, .large])
            }
        }
    }
}

struct LocalFolderContentView: View {
    let node: LocalFolderNode
    let columns: [GridItem]
    let onDelete: (LocalBook) -> Void
    // Interaction Mode:
    // If onSelect is provided, books are Selectable.
    // If onSelect is nil, books are NavigationLinks.
    var onSelect: ((LocalBook) -> Void)? = nil
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 15) {
            // Folders (Always Navigation)
            ForEach(node.children) { child in
                NavigationLink(destination: LocalFolderDetailView(node: child, columns: columns, onDelete: onDelete)) {
                     UnifiedFolderIcon(node: child)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Books
            ForEach(node.books) { book in
                LocalBookItemView(book: book, onSelect: onSelect)
                    .contextMenu {
                        Button(role: .destructive) {
                            onDelete(book)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .padding(.horizontal)
    }
}

struct LocalFolderDetailView: View {
    let node: LocalFolderNode
    let columns: [GridItem]
    let onDelete: (LocalBook) -> Void
    @Environment(\.dismiss) var dismiss
    
    // Preview State for Series View
    @State private var focusedBook: LocalBook?
    @State private var isPreviewExpanded: Bool = true
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header (Preview)
                // Always show Preview if we have a focused book (which we should, defaulting to first)
                if let book = focusedBook {
                     LibraryPreviewHeader(
                        title: "Preview",
                        books: [book], // Single item
                        isExpanded: $isPreviewExpanded,
                        showToggle: true // User requested "less / more deve esserci sempre"
                     )
                }
                
                VStack(alignment: .leading) {
                    Text(node.name)
                        .font(.title2)
                        .bold()
                        .padding(.horizontal)
                    
                    // Grid with Selection Logic
                    LocalFolderContentView(
                        node: node, 
                        columns: columns, 
                        onDelete: onDelete,
                        onSelect: { book in
                            // Update Preview
                            withAnimation {
                                self.focusedBook = book
                            }
                        }
                    )
                }
            }
        }
        .navigationTitle(node.name)
        .onAppear {
            // Default Selection: First Book
            if focusedBook == nil {
                focusedBook = node.books.first
            }
        }
    }
}

// ... LocalFolderCard removed (unused or kept? It was present in file but unused in main flow)
struct LocalFolderCard: View {
    let node: LocalFolderNode
    var showBackground: Bool = true
    
    var body: some View {
        // Resolve Image
        let cover: UIImage? = {
            if let firstBook = node.books.first, let c = firstBook.coverImage, node.children.isEmpty {
                return c
            } else if let random = node.getRandomCovers(count: 1).first {
                return random
            }
            return nil
        }()
        
        // Use Reusable Component
        ComicBoxCard(coverImage: cover, showBackground: showBackground)
    }
}

// Helpers
struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct LocalBookItemView: View {
    let book: LocalBook
    var onSelect: ((LocalBook) -> Void)? = nil
    
    var body: some View {
        // CONTENT
        let content = VStack(alignment: .center, spacing: 8) {
            if let cover = book.coverImage {
                // Robust Cropping: 2:3 Container with Leading Alignment
                Color.clear
                    .aspectRatio(0.66, contentMode: .fit)
                    .overlay(
                        Image(uiImage: cover)
                            .resizable()
                            .aspectRatio(contentMode: .fill),
                        alignment: .trailing
                    )
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .aspectRatio(0.66, contentMode: .fit)
            }
            
            Text(book.title)
                .font(.caption)
                .bold()
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity)
            
            if let issue = book.metadata?.number {
                Text("#\(issue)")
                    .font(.caption2).bold()
                    .foregroundColor(.white)
            }
        }
        
        // INTERACTION WRAPPER
        if let onSelect = onSelect {
            // Selection Mode
            Button(action: {
                onSelect(book)
            }) {
                content
            }
            .buttonStyle(PlainButtonStyle())
        } else {
            // Navigation Mode (Classic)
            NavigationLink(destination: 
                ComicReaderView(bookURL: book.url, bookId: book.id)
                    .toolbar(.hidden, for: .tabBar)
            ) {
                content
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
}

// Re-struct SettingsView for completeness/context (Unchanged functionality, larger fonts)
struct SettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    @AppStorage("skipIntro") private var skipIntro: Bool = false
    @EnvironmentObject var appState: AppState
    
    @State private var isEditing = false
    @State private var showServerPassword = false
    @State private var showGeminiApiKey = false
    
    let customFont = Font.system(size: 20, weight: .regular)
    let headerFont = Font.system(size: 18, weight: .bold)
    
    private func fieldBackground(_ active: Bool) -> Color {
        active ? Color.yellow.opacity(0.15) : Color.clear
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Server Configuration").font(headerFont)) {
                    // Service Name
                    HStack {
                        Text("Service Name").font(customFont)
                        Spacer()
                        TextField("Identificativo", text: $appState.serverName)
                            .multilineTextAlignment(.trailing)
                            .font(customFont)
                            .foregroundColor(isEditing ? .white : .gray)
                            .disabled(!isEditing)
                            .padding(4)
                            .background(fieldBackground(isEditing))
                            .cornerRadius(4)
                    }
                    
                    HStack {
                        Text("Server Address").font(customFont)
                        Spacer()
                        TextField("example.duckdns.org", text: $appState.serverAddress)
                            .multilineTextAlignment(.trailing)
                            .font(customFont)
                            .foregroundColor(isEditing ? .white : .gray)
                            .disabled(!isEditing)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .padding(4)
                            .background(fieldBackground(isEditing))
                            .cornerRadius(4)
                    }
                    
                    HStack {
                        Text("Port").font(customFont)
                        Spacer()
                        TextField("Porta", text: $appState.serverPort)
                            .multilineTextAlignment(.trailing)
                            .font(customFont)
                            .foregroundColor(isEditing ? .white : .gray)
                            .disabled(!isEditing)
                            .keyboardType(.numberPad)
                            .padding(4)
                            .background(fieldBackground(isEditing))
                            .cornerRadius(4)
                    }
                    
                    HStack {
                        Text("User").font(customFont)
                        Spacer()
                        TextField("Username", text: $appState.serverUser)
                            .multilineTextAlignment(.trailing)
                            .font(customFont)
                            .foregroundColor(isEditing ? .white : .gray)
                            .disabled(!isEditing)
                            .autocapitalization(.none)
                            .padding(4)
                            .background(fieldBackground(isEditing))
                            .cornerRadius(4)
                    }
                    
                    HStack {
                        Text("Password").font(customFont)
                        Spacer()
                        if showServerPassword {
                            TextField("Password", text: $appState.serverPassword)
                                .multilineTextAlignment(.trailing)
                                .font(customFont)
                                .foregroundColor(isEditing ? .white : .gray)
                                .disabled(!isEditing)
                                .autocapitalization(.none)
                                .padding(4)
                                .background(fieldBackground(isEditing))
                                .cornerRadius(4)
                        } else {
                            SecureField("Password", text: $appState.serverPassword)
                                .multilineTextAlignment(.trailing)
                                .font(customFont)
                                .foregroundColor(isEditing ? .white : .gray)
                                .disabled(!isEditing)
                                .padding(4)
                                .background(fieldBackground(isEditing))
                                .cornerRadius(4)
                        }
                        
                        if isEditing {
                            Button(action: { showServerPassword.toggle() }) {
                                Image(systemName: showServerPassword ? "eye.slash" : "eye")
                                    .foregroundColor(.yellow)
                                    .frame(width: 30)
                            }
                        }
                    }
                }
                
                Section(header: Text("Translation API Configuration").font(headerFont)) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Gemini API Key").font(customFont)
                            Spacer()
                            if isEditing {
                                Button(action: { showGeminiApiKey.toggle() }) {
                                    Image(systemName: showGeminiApiKey ? "eye.slash" : "eye")
                                        .foregroundColor(.yellow)
                                }
                            }
                        }
                        
                        if showGeminiApiKey {
                            TextField("Incolla qui la chiave", text: $appState.geminiApiKey)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .font(customFont)
                                .foregroundColor(isEditing ? .white : .gray)
                                .disabled(!isEditing)
                                .background(fieldBackground(isEditing))
                                .cornerRadius(4)
                        } else {
                            SecureField("Incolla qui la chiave", text: $appState.geminiApiKey)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .font(customFont)
                                .foregroundColor(isEditing ? .white : .gray)
                                .disabled(!isEditing)
                                .background(fieldBackground(isEditing))
                                .cornerRadius(4)
                        }
                    }
                    
                    HStack {
                        Circle()
                            .fill(GeminiService.shared.isApiKeyValid ? Color.green : Color.red)
                            .frame(width: 16, height: 16)
                        Text("Status").font(customFont)
                        Spacer()
                        Text(GeminiService.shared.validationStatus)
                            .foregroundColor(.secondary)
                            .font(.system(size: 16))
                    }
                    
                    Button(action: {
                        Task { await GeminiService.shared.verifyApiKey() }
                    }) {
                        Text("Verify & Reconnect").font(customFont)
                    }
                    .disabled(isEditing) // Disable verification while editing
                }
                
                Section(header: Text("Application Settings").font(headerFont)) {
                    Toggle("Skip Intro Animation", isOn: $skipIntro)
                        .font(customFont)
                }
                
                Section(header: Text("About").font(headerFont)) {
                    HStack { Text("Version").font(customFont); Spacer(); Text(AppConstants.appVersion).foregroundColor(.secondary).font(customFont) }
                }
            }
            .navigationTitle("Options")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        if isEditing {
                            // Saving logic (reactive via AppStorage, but we can trigger checks)
                            Task {
                                await GeminiService.shared.verifyApiKey()
                            }
                            isEditing = false
                        } else {
                            isEditing = true
                        }
                    }) {
                        Text(isEditing ? "SAVE" : "EDIT")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.yellow)
                    }
                }
                
                // Add a Close button for the sheet case
                ToolbarItem(placement: .navigationBarLeading) {
                    if !isEditing {
                        Button("Close") {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
