import Foundation

/// Represents reading progress for a comic book
struct ReadingProgress: Codable {
    let bookId: String
    var currentPage: Int
    var totalPages: Int
    var lastReadDate: Date
    
    var progressPercentage: Double {
        guard totalPages > 0 else { return 0 }
        return Double(currentPage) / Double(totalPages) * 100
    }
}

/// Manages reading progress persistence using UserDefaults
class ReadingProgressManager {
    static let shared = ReadingProgressManager()
    
    private let userDefaultsKey = "com.phnx.komgareader.readingProgress"
    private var progressCache: [String: ReadingProgress] = [:]
    
    private init() {
        loadProgress()
    }
    
    // MARK: - Public Methods
    
    /// Save or update reading progress for a book
    func saveProgress(bookId: String, currentPage: Int, totalPages: Int) {
        let progress = ReadingProgress(
            bookId: bookId,
            currentPage: currentPage,
            totalPages: totalPages,
            lastReadDate: Date()
        )
        progressCache[bookId] = progress
        persistProgress()
    }
    
    /// Get reading progress for a book
    func getProgress(for bookId: String) -> ReadingProgress? {
        return progressCache[bookId]
    }
    
    /// Check if a book has any reading progress
    func hasProgress(for bookId: String) -> Bool {
        guard let progress = progressCache[bookId] else { return false }
        return progress.currentPage >= 0
    }
    
    /// Get all books with reading progress, sorted by last read date
    func getAllProgress() -> [ReadingProgress] {
        return Array(progressCache.values).sorted { $0.lastReadDate > $1.lastReadDate }
    }
    
    /// Delete progress for a book
    func deleteProgress(for bookId: String) {
        progressCache.removeValue(forKey: bookId)
        persistProgress()
    }
    
    // MARK: - Private Methods
    
    private func loadProgress() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([String: ReadingProgress].self, from: data) else {
            return
        }
        progressCache = decoded
    }
    
    private func persistProgress() {
        guard let encoded = try? JSONEncoder().encode(progressCache) else { return }
        UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
    }
}
