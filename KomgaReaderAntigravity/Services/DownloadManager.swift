import Foundation
import Combine

struct DownloadItem: Identifiable {
    let id: String // Book ID
    let name: String
    let targetFolder: String?
}

class DownloadManager: ObservableObject {
    static let shared = DownloadManager()
    
    @Published var queue: [DownloadItem] = []
    @Published var currentDownload: DownloadItem?
    @Published var progress: Double = 0.0
    @Published var isDownloading: Bool = false
    @Published var isPaused: Bool = false
    @Published var hasNewDownloads: Bool = false // Refresh trigger for Local Library
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {}
    
    func addToQueue(bookId: String, bookName: String, targetFolder: String?) {
        let item = DownloadItem(id: bookId, name: bookName, targetFolder: targetFolder)
        
        // Avoid duplicates in queue
        if !queue.contains(where: { $0.id == bookId }) && currentDownload?.id != bookId {
            queue.append(item)
            // Signal that library is dirty
            // Accessing AppState via EnvironmentObject is hard here as this is a singleton Service.
            // But AppState is an ObservableObject. We can inject it or use a shared reference if available.
            // Since AppState is currently View-bound @StateObject in ContentView passed down...
            // Wait, existing code uses `appState` environment object in Views.
            // Services usually don't access AppState directly unless it's a singleton.
            // Ideally, we observe DownloadManager in AppState?
            // Or we make AppState a shared singleton?
            // User code: "class AppState: ObservableObject". No shared static.
            // Quickest fix: Add `shouldReload` to `DownloadManager` and let `LocalLibraryView` observe it?
            // `LocalLibraryView` already observes `DownloadManager` via `appState`? No.
            // `LocalLibraryView` has `appState`.
            
            // Re-evaluating:
            // I added `shouldReloadLocalLibrary` to `AppState`.
            // But `DownloadManager` cannot see that instance.
            // User suggested: "Flag nel AppState".
            // If I can't reach AppState instance easily...
            // I should add `shouldReload` to `DownloadManager` (which IS a singleton) and have `LocalLibraryView` check THAT.
            // `LocalLibraryView` doesn't strictly observe DownloadManager but it can.
            // Or `ContentView` bridges them.
            
            // ACTUALLY: `DownloadManager.shared` is observable.
            // I will add `public var hasNewDownloads: Bool = false` to DownloadManager.
            // In `LocalLibraryView`, I will check `DownloadManager.shared.hasNewDownloads`.
            // This is cleaner than coupling transparent Service to View State.
            
            // I will undo the change to AppState (or just ignore it) and add it here.
            
            self.hasNewDownloads = true
            
            processQueue()
        }
    }
    
    private func processQueue() {
        // Stop if paused, downloading, or empty
        guard !isPaused, !isDownloading, let next = queue.first else { return }
        
        // Remove from queue and set as current
        queue.removeFirst()
        currentDownload = next
        isDownloading = true
        progress = 0.0
        
        print("⬇️ Starting download: \(next.name)")
        
        Task {
            do {
                _ = try await KomgaService.shared.downloadBook(
                    bookId: next.id,
                    bookName: next.name,
                    toFolder: next.targetFolder
                ) { [weak self] currentProgress in
                    Task { @MainActor in
                        self?.progress = currentProgress
                    }
                }
                
                print("✅ Finished download: \(next.name)")
                await MainActor.run {
                    self.currentDownload = nil
                    self.isDownloading = false
                    self.progress = 0.0
                    // Trigger next
                    self.processQueue() 
                }
            } catch {
                print("❌ Failed download: \(next.name) - \(error)")
                await MainActor.run {
                    self.currentDownload = nil
                    self.isDownloading = false
                    // Try next anyway
                    self.processQueue()
                }
            }
        }
    }
    
    // MARK: - Controls
    
    func pauseDownloads() {
        isPaused = true
    }
    
    func resumeDownloads() {
        isPaused = false
        processQueue()
    }
    
    /// Stops the activity after finishing the current download.
    /// Clears the queue so no further items are processed.
    func stopQueue() {
        // User requested: "finisci il singolo download... e mantenendo cosa scaricato"
        // So we just clear the PENDING queue.
        queue.removeAll()
        // We DO NOT cancel the current download, as requested.
        // Once current finishes, processQueue will run but queue is empty, so it stops.
    }
    
    func cancelAll() {
        queue.removeAll()
    }
}
