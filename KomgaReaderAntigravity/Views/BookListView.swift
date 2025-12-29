import SwiftUI

struct BookListView: View {
    let series: Series
    let libraryName: String
    @Environment(\.dismiss) var dismiss
    @State private var books: [Book] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    // State for Focused Book (Top Hero View)
    @State private var selectedBookId: String?
    
    var focusedBook: Book? {
        books.first(where: { $0.id == selectedBookId })
    }
    
    // State for Multi-Selection
    @State private var selectedBookIds: Set<String> = []
    @State private var isSelectionMode = false
    
    // State for navigation/actions
    @State private var navigationPath = NavigationPath() // If using Stack, but here we use simple states
    @State private var selectedBookURL: URL? // For Reader Navigation
    @State private var downloadingBookId: String?
    @State private var downloadProgress: Double = 0.0
    
    // Download confirmation
    @State private var showImportConfirmation = false
    
    // Conflict Management
    @State private var pendingConflicts: [PendingDownloadItem] = []
    @State private var showConflictAlert = false
    
    // Grid Config - Spacing (15)
    let columns = Array(repeating: GridItem(.flexible(), spacing: 15), count: 5)
    
    // Image Cache
    @State private var bookCovers: [String: UIImage] = [:]

    var body: some View {
        ZStack {
            // Global Background: Blurred Cover
            GeometryReader { geo in
                    if let book = focusedBook, let img = bookCovers[book.id] {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .blur(radius: 20)
                            .opacity(0.4)
                    } else {
                        Color(white: 0.15)
                    }
            }
            .ignoresSafeArea(edges: [.bottom, .horizontal])
            // Overlay simplified dark layer to ensure text contrast
            Color.black.opacity(0.3).ignoresSafeArea(edges: [.bottom, .horizontal])
            
            if isLoading {
                ProgressView("Caricamento...")
                    .colorScheme(.dark)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = errorMessage {
                VStack {
                    Text("Error").foregroundColor(.red)
                    Text(errorMessage).foregroundColor(.white)
                    Button("Retry") { loadBooks() }
                }
            } else {
                // VStack Layout for Zones
                VStack(spacing: 0) {
                    // Zone 2: Breadcrumb Header
                    ZStack {
                        // Background Element for Zone 2
                        Rectangle()
                            .fill(Color.black.opacity(0.4))
                            .overlay(Rectangle().frame(height: 1).foregroundColor(Color.white.opacity(0.1)), alignment: .bottom)
                            .ignoresSafeArea(edges: .top) 
                        
                        HStack {
                            // Back Button (Zone 2 Left)
                            Button(action: { 
                                if isSelectionMode {
                                    isSelectionMode = false
                                    selectedBookIds.removeAll()
                                } else {
                                    dismiss() 
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: isSelectionMode ? "xmark" : "chevron.left")
                                    Text(isSelectionMode ? "Annulla" : "Indietro") // Localized
                                }
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(8)
                            }
                            
                            Spacer()
                            
                            // Select Button (Zone 2 Right)
                            Button(action: {
                                withAnimation {
                                    isSelectionMode.toggle()
                                    if !isSelectionMode {
                                        selectedBookIds.removeAll()
                                    }
                                }
                            }) {
                                Text(isSelectionMode ? "Fine" : "Seleziona")
                                    .font(.headline)
                                    .foregroundColor(.yellow)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        
                        // Centered Title (Series Name)
                        Text(Series.formatSeriesName(series.name))
                            .font(.headline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .allowsHitTesting(false)
                    }
                    .frame(height: 60) // Fixed height
                    
                    // Zone 3: Main Scrolling Content
                    
                    ScrollView {
                         // MARK: - Top Hero Section (Detail View)
                         if let book = focusedBook {
                             HeroDetailView(
                                 book: book,
                                 bookCovers: bookCovers,
                                 onRead: { handleReadRequest() },
                                 onImport: { handleImportRequest() }
                             )
                             .id(book.id) // Force fresh identity
                             
                             // Separator
                             Rectangle()
                                 .fill(Color.white.opacity(0.2))
                                 .frame(height: 1)
                                 .padding(.vertical, 10)
                                 .padding(.horizontal, 20)
                         }

                        // MARK: - Bottom Grid Section
                        LazyVGrid(columns: columns, spacing: 15) { // Spacing 15
                            ForEach(books) { book in
                                VStack(spacing: 8) {
                                    // Cover
                                    ZStack(alignment: .bottomTrailing) {
                                        if let cover = bookCovers[book.id] {
                                            // Robust Cropping: 2:3 Container with Trailing (Right) Alignment
                                            Color.clear
                                                .aspectRatio(0.66, contentMode: .fit)
                                                .overlay(
                                                    Image(uiImage: cover)
                                                        .resizable()
                                                        .aspectRatio(contentMode: .fill),
                                                    alignment: .trailing
                                                )
                                                .clipped()
                                                .contentShape(Rectangle())
                                        } else {
                                             Rectangle().fill(Color.gray.opacity(0.3)).aspectRatio(0.66, contentMode: .fit)
                                        }
                                        // Selection overlay...
                                        if selectedBookIds.contains(book.id) {
                                            ZStack {
                                                Color.black.opacity(0.4)
                                                Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundColor(.yellow)
                                            }
                                            .frame(width: 106, height: 160)
                                        }
                                    }
                                    .aspectRatio(0.66, contentMode: .fit)
                                     .onTapGesture { 
                                         withAnimation {
                                             if isSelectionMode {
                                                 toggleSelection(for: book)
                                             } else {
                                                 selectedBookId = book.id 
                                             }
                                         }
                                     }
                                    .onLongPressGesture { 
                                        withAnimation {
                                            isSelectionMode = true
                                            toggleSelection(for: book)
                                        }
                                    }
                                    
                                    // Custom Metadata Display (Title + Issue)
                                    VStack(spacing: 2) {
                                        Text(book.metadata.title.isEmpty ? book.name : book.metadata.title)
                                            .font(.caption2)
                                            .bold()
                                            .lineLimit(2)
                                             .foregroundColor(selectedBookId == book.id ? .yellow : (isSelectionMode && selectedBookIds.contains(book.id) ? .yellow : .white))
                                            .multilineTextAlignment(.center)
                                        
                                        if !book.metadata.number.isEmpty {
                                            Text("#\(book.metadata.number)")
                                                .font(.caption2)
                                                .bold()
                                                .foregroundColor(.white)
                                        }
                                    }
                                    .frame(width: 106)
                                }
                            }
                        }
                        .padding()
                        .padding(.bottom, 100)
                     }
                }
            }
            
            // Bulk Action Bar (Overlay at bottom)
            if isSelectionMode {
                VStack {
                    Spacer()
                    HStack(spacing: 0) {
                        Button(action: {
                            withAnimation {
                                let allIds = books.map { $0.id }
                                selectedBookIds = Set(allIds)
                            }
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.badge.questionmark")
                                Text("Tutti").font(.caption2).bold()
                            }
                            .foregroundColor(.white)
                            .frame(width: 60)
                        }
                        
                        Spacer()
                        
                        Button(action: { handleImportRequest() }) {
                            HStack {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("Scarica (\(selectedBookIds.count))")
                            }
                            .font(.headline)
                            .foregroundColor(.black)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                            .background(selectedBookIds.isEmpty ? Color.gray : Color.yellow)
                            .cornerRadius(30)
                            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                        }
                        .disabled(selectedBookIds.isEmpty)
                        
                        Spacer()
                        
                        Button(action: {
                            withAnimation {
                                selectedBookIds.removeAll()
                            }
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: "trash")
                                Text("Svuota").font(.caption2).bold()
                            }
                            .foregroundColor(.white)
                            .frame(width: 60)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                    .padding(.bottom, 20) // Safe area padding
                    .background(
                        VisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
                            .overlay(Rectangle().frame(height: 1).foregroundColor(Color.white.opacity(0.1)), alignment: .top)
                            .ignoresSafeArea()
                    )
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onTapGesture {
            // Background tap logic
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { loadBooks() }
        .alert("Import Selected?", isPresented: $showImportConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Import All") {
                importSelectedBooks()
            }
        } message: {
            Text("Import \(selectedBookIds.isEmpty ? 1 : selectedBookIds.count) books to local library?")
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
        // Reader Destination
        .navigationDestination(isPresented: Binding<Bool>(
            get: { selectedBookURL != nil },
            set: { if !$0 { selectedBookURL = nil } }
        )) {
            if let url = selectedBookURL {
                ComicReaderView(bookURL: url, bookId: nil)
            }
        }
    }
    
    // MARK: - Logic
    
    private func loadBooks() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let list = try await KomgaService.shared.fetchBooks(for: series.id)
                self.books = list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                
                if self.selectedBookId == nil || !self.books.contains(where: { $0.id == self.selectedBookId }) {
                    self.selectedBookId = self.books.first?.id
                }
                
                for book in list {
                    if bookCovers[book.id] == nil {
                        if let img = await KomgaService.shared.fetchBookThumbnail(for: book.id) {
                            bookCovers[book.id] = img
                        }
                    }
                }
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
    
    private func toggleSelection(for book: Book) {
        if selectedBookIds.contains(book.id) {
            selectedBookIds.remove(book.id)
        } else {
            selectedBookIds.insert(book.id)
            selectedBookId = book.id // Also focus it
        }
    }
    
    private func handleReadRequest() {
        if let book = focusedBook {
            readRemotely(book: book)
        }
    }
    
    private func handleImportRequest() {
        if !selectedBookIds.isEmpty {
            showImportConfirmation = true
        } else if let book = focusedBook {
            selectedBookIds.insert(book.id)
            showImportConfirmation = true
        }
    }
    
    private func importSelectedBooks() {
        let booksToImport = books.filter { selectedBookIds.contains($0.id) }
        
        // Calculate Target Logic (Consistent with SeriesListView)
        let isOneShot = series.booksCount == 1 // or books.count
        var targetPath = libraryName
        if !isOneShot {
           targetPath += "/" + series.name
        }
        
        var conflicts: [PendingDownloadItem] = []
        
        for book in booksToImport {
            let exists = KomgaService.shared.isFilePresent(bookName: book.name, inFolder: targetPath)
            if exists {
                conflicts.append(PendingDownloadItem(bookId: book.id, bookName: book.name, targetFolder: targetPath))
            } else {
                DownloadManager.shared.addToQueue(
                    bookId: book.id,
                    bookName: book.name,
                    targetFolder: targetPath
                )
                print("Import queued: \(book.name)")
            }
        }
        
        if !conflicts.isEmpty {
            self.pendingConflicts.append(contentsOf: conflicts)
            self.showConflictAlert = true
        }
        
        selectedBookIds.removeAll()
    }
    
    private func readRemotely(book: Book) {
        guard downloadingBookId == nil else { return }
        downloadingBookId = book.id
        
        Task {
            do {
                print("📖 Reading remotely: \(book.name)")
                let cbzURL = try await KomgaService.shared.downloadBook(
                    bookId: book.id,
                    bookName: book.name,
                    toFolder: nil // Temp only
                ) { progress in
                }
                
                let fileManager = FileManager.default
                let tempDir = fileManager.temporaryDirectory.appendingPathComponent("remote_\(book.id)")
                try? fileManager.removeItem(at: tempDir) 
                try KomgaService.shared.unzipBook(at: cbzURL, to: tempDir)
                
                await MainActor.run {
                    self.selectedBookURL = tempDir
                    self.downloadingBookId = nil
                }
                
                try? fileManager.removeItem(at: cbzURL)
                
            } catch {
                print("Read Error: \(error.localizedDescription)")
                downloadingBookId = nil
            }
        }
    }
    
    // MARK: - Conflict Helpers
    private func checkNextConflict() {
        if !pendingConflicts.isEmpty {
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
}

// MARK: - Subviews

struct HeroDetailView: View {
    let book: Book
    let bookCovers: [String: UIImage]
    let onRead: () -> Void
    let onImport: () -> Void
    
    @State private var heroImage: UIImage?
    @State private var isExpanded: Bool = false
    
    init(book: Book, bookCovers: [String : UIImage], onRead: @escaping () -> Void, onImport: @escaping () -> Void) {
        self.book = book
        self.bookCovers = bookCovers
        self.onRead = onRead
        self.onImport = onImport
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
             // Details Split
            HStack(alignment: .top, spacing: 20) {
                // Cover Art
                 Group {
                    if let img = heroImage {
                        Image(uiImage: img)
                            .resizable()
                            .renderingMode(.original)
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 240, height: 360, alignment: .topTrailing)
                            .clipped()
                            .cornerRadius(8)
                            .shadow(radius: 5)
                    } else if let img = bookCovers[book.id] {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 240, height: 360, alignment: .topTrailing)
                            .clipped()
                            .cornerRadius(8)
                            .shadow(radius: 5)
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 240, height: 360)
                            .cornerRadius(8)
                            .overlay(ProgressView())
                    }
                }
                
                // Details Column
                VStack(alignment: .leading, spacing: 8) {
                    // Title
                    Text(book.metadata.title.isEmpty ? book.name : book.metadata.title)
                        .font(.title2)
                        .bold()
                        .foregroundColor(.white)
                    
                    // Number (Styled Bold White)
                    if !book.metadata.number.isEmpty {
                        Text("#\(book.metadata.number)")
                            .font(.title3)
                            .bold()
                            .foregroundColor(.white)
                    }
                    
                    // Metadata Fields
                    Group {
                        if let writer = book.metadata.writer {
                            MetadataRow(label: "Writer:", value: writer)
                        }
                        if let penciller = book.metadata.penciller {
                            MetadataRow(label: "Penciller:", value: penciller)
                        }
                        if let inker = book.metadata.inker {
                            MetadataRow(label: "Inker:", value: inker)
                        }
                    }
                    
                    // Summary with Read More
                    if !book.metadata.summary.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(book.metadata.summary)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.9))
                                .lineLimit(isExpanded ? nil : 4)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            Button(action: { withAnimation { isExpanded.toggle() } }) {
                                Text(isExpanded ? "less..." : "more...")
                                     .font(.caption)
                                     .bold()
                                     .foregroundColor(.yellow)
                            }
                        }
                    }
                    
                    // Action Buttons
                    HStack(spacing: 12) {
                         Button(action: onRead) {
                             Text("Leggi")
                               .font(.headline)
                               .foregroundColor(.black)
                               .frame(minWidth: 120)
                               .padding(.vertical, 12)
                               .background(Color.yellow)
                               .cornerRadius(25)
                         }
                         Button(action: onImport) {
                             Text("Scarica")
                               .font(.headline)
                               .foregroundColor(.white)
                               .frame(minWidth: 120)
                               .padding(.vertical, 12)
                               .background(RoundedRectangle(cornerRadius: 25).stroke(Color.white, lineWidth: 2))
                         }
                    }
                    .padding(.top, 10)
                }
                Spacer()
            }
            .padding(.horizontal)
        }
        .padding(.top, 20)
        .padding(.bottom, 20)
        .task(id: book.id) {
            // Load High Res Cover
            heroImage = nil 
            isExpanded = false // Reset expansion when book changes
            if let img = await KomgaService.shared.fetchBookPageImage(bookId: book.id, pageNumber: 1) {
                heroImage = img
            }
        }
    }
}

struct MetadataRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .top) {
            Text(label).font(.caption).bold().foregroundColor(.gray).frame(width: 70, alignment: .leading)
            Text(value).font(.caption).foregroundColor(.white)
        }
    }
}

// MARK: - VisualEffectView Helper
struct VisualEffectView: UIViewRepresentable {
    var effect: UIVisualEffect?
    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: effect)
        return view
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = effect
    }
}
