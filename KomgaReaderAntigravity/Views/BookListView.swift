import SwiftUI

struct BookListView: View {
    let series: Series
    let libraryName: String
    @Environment(\.dismiss) var dismiss
    @State private var books: [Book] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    // State for Focused Book (Top Hero View)
    @State private var focusedBook: Book?
    
    // State for Multi-Selection
    @State private var selectedBookIds: Set<String> = []
    
    // State for navigation/actions
    @State private var navigationPath = NavigationPath() // If using Stack, but here we use simple states
    @State private var selectedBookURL: URL? // For Reader Navigation
    @State private var downloadingBookId: String?
    @State private var downloadProgress: Double = 0.0
    // State for Metadata Expansion
    @State private var isMetadataExpanded = false
    
    // Download confirmation
    @State private var showImportConfirmation = false
    
    // Conflict Management
    @State private var pendingConflicts: [PendingDownloadItem] = []
    @State private var showConflictAlert = false
    
    // Grid Config - Tighter Spacing (5)
    let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 5)
    
    // Image Cache
    @State private var bookCovers: [String: UIImage] = [:]
    @State private var heroImage: UIImage? = nil // High Res Hero Image

    var body: some View {
        ZStack {
            // Global Background: Blurred Cover
            GeometryReader { geo in
                Group {
                    if let img = heroImage ?? bookCovers[focusedBook?.id ?? ""] {
                        Image(uiImage: img)
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
                            Button(action: { dismiss() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                    Text("Indietro") // Localized
                                }
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(8)
                            }
                            Spacer()
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
                                                 .frame(width: 240, height: 360, alignment: .topLeading)
                                                 .clipped()
                                                 .cornerRadius(8)
                                                 .shadow(radius: 5)
                                                 .opacity(1)
                                         } else if let img = bookCovers[book.id] {
                                             Image(uiImage: img)
                                                 .resizable()
                                                 .aspectRatio(contentMode: .fill)
                                                 .frame(width: 240, height: 360, alignment: .topLeading)
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
                                         if !book.metadata.title.isEmpty {
                                              Text(book.metadata.title).font(.title2).bold().foregroundColor(.white)
                                         } else {
                                              Text(book.name).font(.title2).bold().foregroundColor(.white)
                                         }
                                         
                                         // Number
                                         if !book.metadata.number.isEmpty {
                                             Text("# \(book.metadata.number)") // Space added
                                                 .font(.title3).foregroundColor(.yellow)
                                         }
                                         
                                         // Metadata Fields (Uniform Size)
                                         Group {
                                             if let writer = book.metadata.writer {
                                                 HStack(alignment: .top) {
                                                     Text("Writer:").font(.caption).bold().foregroundColor(.gray).frame(width: 70, alignment: .leading)
                                                     Text(writer).font(.caption).foregroundColor(.white)
                                                 }
                                             }
                                             if let penciller = book.metadata.penciller {
                                                 HStack(alignment: .top) {
                                                     Text("Penciller:").font(.caption).bold().foregroundColor(.gray).frame(width: 70, alignment: .leading)
                                                     Text(penciller).font(.caption).foregroundColor(.white)
                                                 }
                                             }
                                             if let inker = book.metadata.inker {
                                                 HStack(alignment: .top) {
                                                     Text("Inker:").font(.caption).bold().foregroundColor(.gray).frame(width: 70, alignment: .leading)
                                                     Text(inker).font(.caption).foregroundColor(.white)
                                                 }
                                             }
                                         }
                                         
                                         // Summary with Read More
                                         if !book.metadata.summary.isEmpty {
                                             VStack(alignment: .leading, spacing: 4) {
                                                 Text(book.metadata.summary)
                                                     .font(.caption) // Reduced size
                                                     .foregroundColor(.white.opacity(0.9))
                                                     .lineLimit(isMetadataExpanded ? nil : 4)
                                                     .fixedSize(horizontal: false, vertical: true) // Allow growth
                                                 
                                                 Button(action: { withAnimation { isMetadataExpanded.toggle() } }) {
                                                     Text(isMetadataExpanded ? "less..." : "more...")
                                                         .font(.caption)
                                                         .bold()
                                                         .foregroundColor(.yellow)
                                                 }
                                             }
                                         }
                                         
                                          // Action Buttons (60% Wider)
                                         HStack(spacing: 12) {
                                              Button(action: { handleReadRequest() }) {
                                                  Text("Leggi")
                                                    .font(.headline)
                                                    .foregroundColor(.black)
                                                    .frame(minWidth: 120) // Increased width
                                                    .padding(.vertical, 12)
                                                    .background(Color.yellow)
                                                    .cornerRadius(25)
                                              }
                                              Button(action: { handleImportRequest() }) {
                                                  Text("Scarica")
                                                    .font(.headline)
                                                    .foregroundColor(.white)
                                                    .frame(minWidth: 120) // Increased width
                                                    .padding(.vertical, 12)
                                                    .background(RoundedRectangle(cornerRadius: 25).stroke(Color.white, lineWidth: 2))
                                              }
                                         }
                                         .padding(.top, 10)
                                     }
                                     Spacer() // Push everything to the left
                                }
                                .padding(.horizontal)
                            }
                            .padding(.bottom, 20)
                            .padding(.top, 20)
                            
                            // Separator
                            Rectangle()
                                .fill(Color.white.opacity(0.2))
                                .frame(height: 1)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 20)
                         }

                        // MARK: - Bottom Grid Section
                        LazyVGrid(columns: columns, spacing: 20) { // Spacing 20
                            ForEach(books) { book in
                                VStack(spacing: 8) {
                                    // Cover
                                    ZStack(alignment: .bottomTrailing) {
                                        if let img = bookCovers[book.id] {
                                            Image(uiImage: img)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 106, height: 160, alignment: .trailing)
                                                .clipped()
                                                .contentShape(Rectangle())
                                        } else {
                                             Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 106, height: 160)
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
                                    .frame(width: 106, height: 160)
                                    .onTapGesture { focusedBook = book }
                                    .onLongPressGesture { toggleSelection(for: book) }
                                    
                                    // Custom Metadata Display (Title + Issue)
                                    VStack(spacing: 2) {
                                        Text(book.metadata.title.isEmpty ? book.name : book.metadata.title)
                                            .font(.caption2)
                                            .bold()
                                            .lineLimit(2)
                                            .foregroundColor(focusedBook?.id == book.id ? .yellow : .white)
                                            .multilineTextAlignment(.center)
                                        
                                        if !book.metadata.number.isEmpty {
                                            Text("#\(book.metadata.number)")
                                                .font(.caption2)
                                                .foregroundColor(.gray)
                                        }
                                    }
                                    .frame(width: 106)
                                }
                            }
                        }
                        .padding()
                        .padding(.bottom, 40)
                     }
                }
                .onChange(of: focusedBook) { newBook in
                    guard let book = newBook else { return }
                    heroImage = nil 
                    Task {
                        heroImage = await KomgaService.shared.fetchBookPageImage(bookId: book.id, pageNumber: 1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onTapGesture {
            selectedBookIds.removeAll()
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
                
                if self.focusedBook == nil || !self.books.contains(where: { $0.id == self.focusedBook?.id }) {
                    self.focusedBook = self.books.first
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
            focusedBook = book // Also focus it
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
