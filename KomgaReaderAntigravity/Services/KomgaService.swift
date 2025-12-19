import Foundation
import ZIPFoundation

struct PageWrapper<T: Codable>: Codable {
    let content: [T]
    let empty: Bool?
    let first: Bool?
    let last: Bool?
    let number: Int?
    let numberOfElements: Int?
    let size: Int?
    let totalElements: Int?
    let totalPages: Int
}

class KomgaService: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let shared = KomgaService()
    
    private var baseURL: URL {
        let address = UserDefaults.standard.string(forKey: "serverAddress") ?? "phnx-komga-mi.duckdns.org"
        let port = UserDefaults.standard.string(forKey: "serverPort") ?? "8443"
        return URL(string: "https://\(address):\(port)/api/v1") ?? URL(string: "https://phnx-komga-mi.duckdns.org:8443/api/v1")!
    }
    
    private var username: String {
        return UserDefaults.standard.string(forKey: "serverUser") ?? "admin"
    }
    
    private var password: String {
        return UserDefaults.standard.string(forKey: "serverPassword") ?? "admin"
    }

    
    enum KomgaError: Error, LocalizedError {
        case authenticationFailed
        case unknown(String)
        
        var errorDescription: String? {
            switch self {
            case .authenticationFailed:
                return "Authentication failed. Please check your username and password in KomgaService.swift."
            case .unknown(let message):
                return message
            }
        }
    }
    
    private var session: URLSession!
    private var downloadContinuations: [Int: CheckedContinuation<URL, Error>] = [:]
    private var downloadProgressCallbacks: [Int: (Double) -> Void] = [:]
    
    // Simple In-Memory Cache
    private var seriesCache: [String: [Series]] = [:] // LibraryID -> [Series]
    private var booksCache: [String: [Book]] = [:]   // SeriesID -> [Book]
    
    // MARK: - Helper Methods
    
    /// Returns the base directory (Documents - iOS creates ACR folder automatically)
    private func getACRBaseURL() -> URL {
        // iOS creates a folder with CFBundleDisplayName ("ACR") automatically
        // So Documents IS our ACR folder
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    /// Returns the URL for the local library directory (Library)
    /// This folder contains downloaded comics organized by series
    func getLocalLibraryURL() -> URL {
        return getACRBaseURL().appendingPathComponent("Library")
    }
    
    /// Returns the URL for temporary files (tmp)
    /// Used for remote reading and temporary operations
    func getTempLibraryURL() -> URL {
        return getACRBaseURL().appendingPathComponent("tmp")
    }
    
    // Shared Decoder
    private lazy var decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        // decoder.keyDecodingStrategy = .convertFromSnakeCase // REMOVED: Server returns camelCase
        return decoder
    }()
    
    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        
        // Create ACR directory structure
        let fileManager = FileManager.default
        let libraryURL = getLocalLibraryURL()
        let tmpURL = getTempLibraryURL()
        
        // Create Library directory
        if !fileManager.fileExists(atPath: libraryURL.path) {
            try? fileManager.createDirectory(at: libraryURL, withIntermediateDirectories: true, attributes: nil)
            print("📁 Created ACR/Library directory at: \(libraryURL.path)")
        }
        
        // Create tmp directory
        if !fileManager.fileExists(atPath: tmpURL.path) {
            try? fileManager.createDirectory(at: tmpURL, withIntermediateDirectories: true, attributes: nil)
            print("📁 Created ACR/tmp directory at: \(tmpURL.path)")
        }
    }
    
    // MARK: - Helpers
    
    private func makeRequest(url: URL, method: String = "GET", body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        
        // Basic Auth
        let loginString = String(format: "%@:%@", username, password)
        let loginData = loginString.data(using: String.Encoding.utf8)!
        let base64LoginString = loginData.base64EncodedString()
        request.setValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")
        
        if let body = body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        
        return request
    }
    
    // MARK: - API Calls
    
    @MainActor
    func fetchLibraries() async throws -> [Library] {
        let url = baseURL.appendingPathComponent("libraries")
        let request = makeRequest(url: url)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw KomgaError.authenticationFailed
            }
            guard httpResponse.statusCode == 200 else {
                throw KomgaError.unknown("Server error: \(httpResponse.statusCode)")
            }
        }
        
        let libraries = try decoder.decode([Library].self, from: data)
        return libraries
    }
    
    @MainActor
    func fetchSeries(for libraryId: String) async throws -> [Series] {
        // Return cached if available
        if let cached = seriesCache[libraryId], !cached.isEmpty {
            return cached
        }
        
        // CHANGE: Use GET /series because POST /series/list search filter was unreliable
        var components = URLComponents(url: baseURL.appendingPathComponent("series"), resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "library_id", value: libraryId), // Revert to standard library_id
            URLQueryItem(name: "size", value: "500")
        ]
        
        guard let url = components.url else { throw KomgaError.unknown("Invalid URL") }
        
        print("DEBUG: Fetching Series URL: \(url.absoluteString)")
        
        let request = makeRequest(url: url, method: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            print("DEBUG: Status Code: \(httpResponse.statusCode)")
        }
        
        // if let jsonString = String(data: data, encoding: .utf8) {
        //    print("DEBUG: Raw JSON: \(jsonString)")
        // }
        
        do {
            let page = try decoder.decode(PageWrapper<Series>.self, from: data)
            let list = page.content
            print("✅ DEBUG: Successfully Decoded \(list.count) series")
            
            // Save to cache
            seriesCache[libraryId] = list
            return list
        } catch {
            print("❌ DEBUG: Decoding Error: \(error)")
            throw error
        }
    }
    
    @MainActor
    func fetchBooks(for seriesId: String) async throws -> [Book] {
        // Return cached if available
        if let cached = booksCache[seriesId], !cached.isEmpty {
            return cached
        }
        
        // Fix: Use 'size' param to get all books
        let url = baseURL.appendingPathComponent("series").appendingPathComponent(seriesId).appendingPathComponent("books")
        
        // Komga default size is 20. We want all.
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        components.queryItems = [URLQueryItem(name: "size", value: "500")] // Just in case
        
        let request = makeRequest(url: components.url!)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        let page = try decoder.decode(PageWrapper<Book>.self, from: data)
        let list = page.content
        
        // Save to cache
        booksCache[seriesId] = list
        return list
    }
    
    // Fetch ALL books for a library (used for path mapping)
    // Warning: This can be heavy for large libraries.
    @MainActor
    func fetchAllBooks(for libraryId: String) async throws -> [Book] {
        var allBooks: [Book] = []
        var pageNumber = 0
        let pageSize = 2000
        var totalPages = 1
        
        repeat {
            var components = URLComponents(url: baseURL.appendingPathComponent("books"), resolvingAgainstBaseURL: true)!
            components.queryItems = [
                URLQueryItem(name: "library_id", value: libraryId),
                URLQueryItem(name: "size", value: String(pageSize)),
                URLQueryItem(name: "page", value: String(pageNumber))
            ]
            
            let request = makeRequest(url: components.url!)
            let (data, _) = try await URLSession.shared.data(for: request)
            let page = try decoder.decode(PageWrapper<Book>.self, from: data)
            
            allBooks.append(contentsOf: page.content)
            totalPages = page.totalPages
            pageNumber += 1
            
            // DEBUG: Trace progress
            print("📚 Fetched page \(pageNumber)/\(totalPages) (\(page.content.count) books). Total so far: \(allBooks.count)")
            
        } while pageNumber < totalPages
        
        return allBooks
    }
    

    
    // MARK: - Helpers for UI
    
    @MainActor
    func fetchRandomBookThumbnail(for libraryId: String) async -> UIImage? {
        let key = "lib_thumb_\(libraryId)"
        if let cached = ImageCacheService.shared.getImage(forKey: key) { return cached }
        
        do {
            let series = try await fetchSeries(for: libraryId)
            guard let firstSeries = series.first else { return nil }
            if let image = await fetchRandomBookThumbnail(forSeries: firstSeries.id) {
                ImageCacheService.shared.saveImage(image, forKey: key)
                return image
            }
            return nil
        } catch {
            print("Failed to fetch thumb for library \(libraryId): \(error)")
            return nil
        }
    }
    
    @MainActor
    func fetchRandomBookThumbnail(forSeries seriesId: String) async -> UIImage? {
        let key = "series_thumb_\(seriesId)"
        if let cached = ImageCacheService.shared.getImage(forKey: key) { return cached }
        
        do {
            let books = try await fetchBooks(for: seriesId)
            guard let firstBook = books.first else { return nil }
            // Ensure we use the book fetch which now caches too, but we want to map it to series key
            if let image = await fetchBookThumbnail(for: firstBook.id) {
                ImageCacheService.shared.saveImage(image, forKey: key)
                return image
            }
            return nil
        } catch {
            return nil
        }
    }
    
    @MainActor
    func fetchBookThumbnail(for bookId: String) async -> UIImage? {
        let key = "book_thumb_\(bookId)"
        // 1. Check Cache
        if let cached = ImageCacheService.shared.getImage(forKey: key) {
            return cached
        }
        
        // 2. Fetch from Network
        let url = baseURL.appendingPathComponent("books").appendingPathComponent(bookId).appendingPathComponent("thumbnail")
        let request = makeRequest(url: url)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let image = UIImage(data: data) {
                // 3. Save to Cache
                ImageCacheService.shared.saveImage(image, forKey: key)
                return image
            }
            return nil
        } catch {
            return nil
        }
    }
    
    // Fetch specifically the first page as a high-quality cover
    @MainActor
    func fetchBookPageImage(bookId: String, pageNumber: Int = 1) async -> UIImage? {
        let key = "book_page_\(bookId)_\(pageNumber)"
        if let cached = ImageCacheService.shared.getImage(forKey: key) { return cached }
        
        // endpoint: /api/v1/books/{bookId}/pages/{pageNumber}
        let url = baseURL.appendingPathComponent("books").appendingPathComponent(bookId).appendingPathComponent("pages").appendingPathComponent("\(pageNumber)")
        let request = makeRequest(url: url)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let image = UIImage(data: data) {
                ImageCacheService.shared.saveImage(image, forKey: key)
                return image
            }
            return nil
        } catch {
            print("Failed to fetch page \(pageNumber) for book \(bookId): \(error)")
            return nil
        }
    }
    
    // MARK: - Download & Unzip
    
    func downloadBook(bookId: String, bookName: String, toFolder folderPath: String? = nil, progress: ((Double) -> Void)? = nil) async throws -> URL {
        let url = baseURL.appendingPathComponent("books").appendingPathComponent(bookId).appendingPathComponent("file")
        let request = makeRequest(url: url)
        
        return try await withCheckedThrowingContinuation { continuation in
            let task = session.downloadTask(with: request)
            
            // Store callbacks with metadata
            downloadContinuations[task.taskIdentifier] = continuation
            if let progress = progress {
                downloadProgressCallbacks[task.taskIdentifier] = progress
            }
            
            // Store book metadata for later use in delegate
            let metadata = DownloadMetadata(bookName: bookName, folderPath: folderPath)
            downloadMetadata[task.taskIdentifier] = metadata
            
            task.resume()
        }
    }
    
    // Metadata for downloads
    private struct DownloadMetadata {
        let bookName: String
        let folderPath: String?
    }
    private var downloadMetadata: [Int: DownloadMetadata] = [:]
    
    // MARK: - URLSessionDownloadDelegate
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let continuation = downloadContinuations[downloadTask.taskIdentifier] else { return }
        guard let metadata = downloadMetadata[downloadTask.taskIdentifier] else {
            continuation.resume(throwing: NSError(domain: "KomgaService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing download metadata"]))
            cleanup(task: downloadTask)
            return
        }
        
        // Move file to permanent location in LocalLibrary
        do {
            let fileManager = FileManager.default
            let localLibraryURL = getLocalLibraryURL()
            
            // Determine destination folder
            // Determine destination folder
            let destinationFolder: URL
            if let folderPath = metadata.folderPath {
                // Robustly construct path by splitting components
                // appendingPathComponent escapes slashes ("A/B" -> "A%2FB"), which we don't want for paths.
                var url = localLibraryURL
                let components = folderPath.split(separator: "/")
                for component in components {
                    url.appendPathComponent(String(component))
                }
                destinationFolder = url
                try fileManager.createDirectory(at: destinationFolder, withIntermediateDirectories: true, attributes: nil)
            } else {
                destinationFolder = localLibraryURL
            }
            
            // Clean filename and add .cbz extension if needed
            var filename = metadata.bookName
            if !filename.hasSuffix(".cbz") && !filename.hasSuffix(".cbr") {
                filename += ".cbz"
            }
            
            let destinationURL = destinationFolder.appendingPathComponent(filename)
            
            // Remove existing file if present
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            
            try fileManager.moveItem(at: location, to: destinationURL)
            
            print("✅ Downloaded: \(destinationURL.path)")
            continuation.resume(returning: destinationURL)
        } catch {
            continuation.resume(throwing: error)
        }
        
        cleanup(task: downloadTask)
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let progressCallback = downloadProgressCallbacks[downloadTask.taskIdentifier] else { return }
        
        if totalBytesExpectedToWrite > 0 {
            let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            progressCallback(p)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            if let continuation = downloadContinuations[task.taskIdentifier] {
                continuation.resume(throwing: error)
                cleanup(task: task)
            }
        }
    }
    
    private func cleanup(task: URLSessionTask) {
        downloadContinuations.removeValue(forKey: task.taskIdentifier)
        downloadProgressCallbacks.removeValue(forKey: task.taskIdentifier)
        downloadMetadata.removeValue(forKey: task.taskIdentifier)
    }
    
    func unzipBook(at sourceURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true, attributes: nil)
        
        try fileManager.unzipItem(at: sourceURL, to: destinationURL)
    }
    
    /// Extracts a specific file from the archive to a destination URL
    func extractFile(named fileName: String, from archiveURL: URL, to destinationURL: URL) -> Bool {
        let fileManager = FileManager.default
        guard let archive = Archive(url: archiveURL, accessMode: .read) else { return false }
        
        guard let entry = archive[fileName] else { return false }
        
        do {
            _ = try archive.extract(entry, to: destinationURL)
            return true
        } catch {
            print("Failed to extract \(fileName): \(error)")
            return false
        }
    }
    
    // MARK: - Existence Check Helper
    public func isFilePresent(bookName: String, inFolder folderPath: String?) -> Bool {
        let fileManager = FileManager.default
        let localLibraryURL = getLocalLibraryURL()
        
        var destinationFolder = localLibraryURL
        if let folderPath = folderPath {
            let components = folderPath.split(separator: "/")
            for component in components {
                destinationFolder.appendPathComponent(String(component))
            }
        }
        
        var filename = bookName
        if !filename.hasSuffix(".cbz") && !filename.hasSuffix(".cbr") {
             filename += ".cbz"
        }
        
        let destinationURL = destinationFolder.appendingPathComponent(filename)
        return fileManager.fileExists(atPath: destinationURL.path)
    }
}
