class ComicMetadataService {
    static let shared = ComicMetadataService()
    
    func parseComicInfo(at url: URL) -> ComicInfo? {
        let xmlURL = url.appendingPathComponent("ComicInfo.xml")
        guard FileManager.default.fileExists(atPath: xmlURL.path) else { return nil }
        
        do {
            let data = try Data(contentsOf: xmlURL)
            return ComicInfoParser.parse(data: data)
        } catch {
            print("Error reading ComicInfo.xml: \(error)")
            return nil
        }
    }
}
