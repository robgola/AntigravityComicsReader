import Foundation
import UIKit
import Vision

class SplashBackgroundService {
    static let shared = SplashBackgroundService()
    
    // Persistent Cache URL
    private var splashCacheURL: URL {
        let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let docURL = urls[0]
        let cacheDir = docURL.appendingPathComponent("SplashCache")
        // Ensure it exists
        if !FileManager.default.fileExists(atPath: cacheDir.path) {
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
        return cacheDir
    }

    // 1. Get Images for Startup (Fast, from Disk)
    func getSplashImages(count: Int = 15) async -> [UIImage] {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: splashCacheURL, includingPropertiesForKeys: nil) else {
            return []
        }
        
        let imageFiles = files.filter { ["jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) }
        
        // If we have enough cached images, use them immediately
        if !imageFiles.isEmpty {
            let shuffled = imageFiles.shuffled().prefix(count)
            var images: [UIImage] = []
            for url in shuffled {
                if let img = UIImage(contentsOfFile: url.path) {
                    images.append(img)
                }
            }
            print("🚀 Loaded \(images.count) splash images from persistent cache.")
            return images
        } else {
            // Fallback for very first run: Scan temp/library if empty
            // But usually this returns empty and lets the background updater fill it for next time.
            return []
        }
    }
    
    // 2. Update Cache in Background (Refreshes the pool for Next Launch)
    func updateSplashCache() {
        Task.detached(priority: .background) {
            print("🔄 Updating Splash Cache in background...")
            let allImages = await self.scanForImageURLs()
            guard !allImages.isEmpty else { return }
            
            // Pick 20 random images to save for next time
            let candidates = allImages.shuffled().prefix(20)
            
            let fileManager = FileManager.default
            let cacheDir = self.splashCacheURL
            
            // Clear old cache first? Or just overwrite/add? 
            // Better to clean to avoid stale huge files.
            if let oldFiles = try? fileManager.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil) {
                for file in oldFiles {
                    try? fileManager.removeItem(at: file)
                }
            }
            
            // Save new ones
            for (index, url) in candidates.enumerated() {
                if let data = try? Data(contentsOf: url) {
                    let filename = "splash_\(index).jpg" // normalizing to jpg or keeping extension?
                    // actually just copy the file or write data? 
                    // reading data is safer to ensure valid image file
                    let destination = cacheDir.appendingPathComponent(filename)
                    try? data.write(to: destination)
                }
            }
            print("✅ Splash Cache updated with \(candidates.count) images.")
        }
    }
    
    // Helper to scan files synchronously (unchanged logic, just returns URLs)
    nonisolated private func scanForImageURLs() async -> [URL] {
        let fileManager = FileManager.default
        // scan Library (Documents) recursive
        let docURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        // We want to scan actual comics, not just cached unzips?
        // Actually, previous logic scanned Temp directory "reading_...".
        // That only works if books are OPEN.
        // Better to scan LocalLibrary folder for unzipped books if possible, 
        // OR just keep scanning temp.
        // If the user wants "random pages from library", scanning cbz files is hard without unzipping.
        // So sticking to "recently read/opened" (Temp) is a good proxy, OR 
        // we can peek into "KomgaReader/LocalLibrary" if we decide to maintain unzipped versions.
        // For now, let's keep scanning Temp as it was, but ALSO scan the Library folder if we implement unzipping there.
        // Wait, the user said "memorizzerei... nel dir temp". 
        // But Temp gets cleared by OS. Documents/SplashCache is safer.
        
        // Let's stick to scanning valid images in Temp for now (Reading sessions) + any previously cached ones?
        // Actually, if we only scan Temp, we only get images if the user has read something this session.
        // Challenge: If Fresh Start, Temp is empty.
        // So we might want to "prefetch" some random book if cache is empty?
        // For now, let's stick to the previous scanning logic but persist the result.
        
        var collectedURLs: [URL] = []
        let tempURL = fileManager.temporaryDirectory
        
        guard let items = try? fileManager.contentsOfDirectory(at: tempURL, includingPropertiesForKeys: nil) else { return [] }
        
        for item in items where item.lastPathComponent.hasPrefix("reading_") || item.lastPathComponent.hasPrefix("remote_") {
            if let enumerator = fileManager.enumerator(at: item, includingPropertiesForKeys: nil) {
                for case let fileURL as URL in enumerator {
                    let ext = fileURL.pathExtension.lowercased()
                    if ["jpg", "jpeg", "png", "webp"].contains(ext) {
                        collectedURLs.append(fileURL)
                    }
                }
            }
        }
        return collectedURLs
    }
    
//    private func countTextObservations(in image: UIImage) async -> Int { ... } // Removed as unused optimization
}
