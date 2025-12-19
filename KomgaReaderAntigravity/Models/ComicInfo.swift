import Foundation

struct ComicInfo: Codable, Hashable, Sendable {
    var title: String = ""
    var series: String = ""
    var number: String = ""
    var volume: String = ""
    var summary: String = ""
    var writer: String?
    var penciller: String?
    var inker: String?
    var colorist: String?
    var letterer: String?
    var publisher: String?
    var genre: String?
    var year: Int?
    var month: Int?
}

class ComicInfoParser: NSObject, XMLParserDelegate {
    private var currentElement = ""
    private var comicInfo = ComicInfo()
    private var currentValue = ""
    
    static func parse(data: Data) -> ComicInfo {
        let parser = XMLParser(data: data)
        let delegate = ComicInfoParser()
        parser.delegate = delegate
        parser.parse()
        return delegate.comicInfo
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        currentValue = ""
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentValue += string
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let val = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "Title": comicInfo.title = val
        case "Series": comicInfo.series = val
        case "Number": comicInfo.number = val
        case "Volume": comicInfo.volume = val
        case "Summary": comicInfo.summary = val
        case "Writer": comicInfo.writer = val
        case "Penciller": comicInfo.penciller = val
        case "Inker": comicInfo.inker = val
        case "Colorist": comicInfo.colorist = val
        case "Letterer": comicInfo.letterer = val
        case "Publisher": comicInfo.publisher = val
        case "Genre": comicInfo.genre = val
        case "Year": comicInfo.year = Int(val)
        case "Month": comicInfo.month = Int(val)
        default: break
        }
    }
}
