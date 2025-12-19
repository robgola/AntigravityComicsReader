import Foundation

// MARK: - Library
struct Library: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let root: String
}

// MARK: - Series
struct Series: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let libraryId: String
    let name: String
    let booksCount: Int
    let url: String
    let metadata: SeriesMetadata
    
    // Formatting Helper
    static func formatSeriesName(_ name: String) -> String {
        // "1998 Danger Girl" -> "Danger Girl Vol.1998"
        let pattern = #"^(\d{4})\s+(.+)$"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(location: 0, length: name.utf16.count)
            if let match = regex.firstMatch(in: name, options: [], range: range) {
                if let yearRange = Range(match.range(at: 1), in: name),
                   let titleRange = Range(match.range(at: 2), in: name) {
                    let year = String(name[yearRange])
                    let title = String(name[titleRange])
                    return "\(title) Vol.\(year)"
                }
            }
        }
        return name
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        libraryId = try container.decode(String.self, forKey: .libraryId)
        name = try container.decode(String.self, forKey: .name)
        booksCount = try container.decodeIfPresent(Int.self, forKey: .booksCount) ?? 0
        metadata = try container.decodeIfPresent(SeriesMetadata.self, forKey: .metadata) ?? SeriesMetadata(status: "", summary: "")
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
    }

    struct SeriesMetadata: Codable, Hashable, Sendable {
        let status: String
        let summary: String
        let publisher: String // NEW
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
            summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
            publisher = try container.decodeIfPresent(String.self, forKey: .publisher) ?? ""
        }
        
        init(status: String, summary: String, publisher: String = "") {
            self.status = status
            self.summary = summary
            self.publisher = publisher
        }
    }
}

// MARK: - Book
struct Book: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let seriesId: String
    let name: String
    let number: Int
    let url: String
    let media: BookMedia
    let metadata: BookMetadata
    
    struct BookMedia: Codable, Hashable, Sendable {
        let status: String
        let mediaType: String
        let pagesCount: Int
    }
    
    struct BookMetadata: Codable, Hashable, Sendable {
        let title: String
        let summary: String
        let number: String
        let releaseDate: String?
        // Authors are decoded from a list
        let authors: [Author]
        
        // Computed properties for UI
        var writer: String? { authors.first(where: { $0.role.lowercased() == "writer" })?.name }
        var penciller: String? { authors.first(where: { $0.role.lowercased() == "penciller" })?.name }
        var inker: String? { authors.first(where: { $0.role.lowercased() == "inker" })?.name }
        
        var displayTitle: String {
             return title.isEmpty ? "" : title
        }
        
        struct Author: Codable, Hashable, Sendable {
            let name: String
            let role: String
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
            summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
            number = try container.decodeIfPresent(String.self, forKey: .number) ?? ""
            releaseDate = try container.decodeIfPresent(String.self, forKey: .releaseDate)
            authors = try container.decodeIfPresent([Author].self, forKey: .authors) ?? []
        }
        
        // Default init for placeholders
        init(title: String = "", summary: String = "", number: String = "", authors: [Author] = []) {
            self.title = title
            self.summary = summary
            self.number = number
            self.releaseDate = nil
            self.authors = authors
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        seriesId = try container.decode(String.self, forKey: .seriesId)
        name = try container.decode(String.self, forKey: .name)
        number = try container.decodeIfPresent(Int.self, forKey: .number) ?? 0
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        media = try container.decodeIfPresent(BookMedia.self, forKey: .media) ?? BookMedia(status: "", mediaType: "", pagesCount: 0)
        metadata = try container.decodeIfPresent(BookMetadata.self, forKey: .metadata) ?? BookMetadata()
    }
}

// MARK: - Page (for future use if needed, though we unzip)
struct Page: Codable, Identifiable, Hashable, Sendable {
    let number: Int
    let fileName: String
    let mediaType: String
    
    var id: Int { number }
}
