import Foundation
import Combine
import SwiftUI
import UIKit

class GeminiService: ObservableObject {
    static let shared = GeminiService()
    
    @Published var isApiKeyValid: Bool = false
    @Published var validationStatus: String = "Checking..."
    @Published var lastRawResponse: String = "" // Debug: Store raw JSON
    @Published var lastMarkedImage: UIImage? = nil // Debug: Store marked image
    
    private var apiKey: String {
        return UserDefaults.standard.string(forKey: "geminiApiKey") ?? ""
    }
    // Using gemini-2.5-flash (User requested and verified via screenshot)
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
    
    // ... rest of init ...


    
    private init() {
         Task {
            await verifyApiKey()
         }
    }
    
    func verifyApiKey() async {
        // Validation: Ensure valid length (Gemini keys are usually ~39 chars)
        guard !apiKey.isEmpty && apiKey.count > 20 else {
            await MainActor.run {
                self.isApiKeyValid = false
                self.validationStatus = "Missing API Key"
            }
            return
        }
        
        // 1. Try to generate content
        let urlString = "\(baseURL)?key=\(apiKey)"
        guard let url = URL(string: urlString) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "contents": [
                ["parts": [["text": "Hello"]]]
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                await MainActor.run {
                    self.isApiKeyValid = true
                    self.validationStatus = "Valid (Gemini 1.5 Flash)"
                }
            } else {
                let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("Gemini Verification Error: \(errorMsg)")
                
                // 2. If 404, try to list models to see what's available
                if (response as? HTTPURLResponse)?.statusCode == 404 {
                    await listAvailableModels()
                }
                
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                
                // Special handling for 429 (Rate Limit): Key is valid, just busy.
                if code == 429 {
                    await MainActor.run {
                        self.isApiKeyValid = true
                        self.validationStatus = "Rate Limited (Wait)"
                    }
                } else {
                    await MainActor.run {
                        self.isApiKeyValid = false
                        self.validationStatus = "Error: \(code)"
                    }
                }
            }
        } catch {
            await MainActor.run {
                self.isApiKeyValid = false
                self.validationStatus = "Connection: \(error.localizedDescription)"
            }
        }
    }
    
    private func listAvailableModels() async {
        let listURLString = "https://generativelanguage.googleapis.com/v1beta/models?key=\(apiKey)"
        guard let url = URL(string: listURLString) else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data)
            print("Available Models: \(json)")
        } catch {
            print("Failed to list models: \(error)")
        }
    }
    
    struct GeminiResponse: Codable {
        let candidates: [Candidate]?
        
        struct Candidate: Codable {
            let content: Content
        }
        
        struct Content: Codable {
            let parts: [Part]
        }
        
        struct Part: Codable {
            let text: String
        }
    }
    
    struct TranslationResult: Codable {
        let translatedText: String
        let fontStyle: String // "bold", "italic", "handwritten", "computer", "shout"
    }
    
    func translate(text: String, context: String = "", to targetLanguage: String = "Italian") async throws -> TranslationResult {
        // Removed strict guard to allow lazy validation
        // guard isApiKeyValid else { ... }
        
        let urlString = "\(baseURL)?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            await MainActor.run {
                self.isApiKeyValid = false
                self.validationStatus = "Invalid URL"
            }
            throw NSError(domain: "GeminiService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let systemPrompt = """
        You are an expert comic book translator specializing in localization from American English to Italian.
        Your goal is to translate the text FAITHFULLY and analyze the font style.
        
        Input: English text from a comic bubble.
        Output: JSON object with:
        - "translatedText": The Italian translation.
        - "fontStyle": One of ["bold", "italic", "handwritten", "computer", "shout", "normal"].
        
        Rules:
        1. Translate FAITHFULLY into Italian. No paraphrasing.
        2. Keep sound effects as is.
        3. Do NOT translate proper names.
        4. "fontStyle" analysis:
           - "shout": All caps with exclamation marks, aggressive.
           - "computer": Monospaced, square, robotic.
           - "bold": Heavy emphasis.
           - "handwritten": Standard comic speech.
           - "italic": Whispers or thoughts or emphasis.
        5. Output ONLY valid JSON. No markdown fencing.
        """
        
        let userPrompt = """
        Context so far:
        \(context)
        
        Text:
        "\(text)"
        """
        
        let fullPrompt = "\(systemPrompt)\n\n\(userPrompt)"
        
        let body: [String: Any] = [
            "contents": [
                ["parts": [["text": fullPrompt]]]
            ],
            "generationConfig": [
                "temperature": 0.4
                // Note: responseMimeType is not supported in v1 API
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            let code = (response as? HTTPURLResponse)?.statusCode ?? 500
            
            await MainActor.run {
                if code == 401 || code == 403 {
                    self.isApiKeyValid = false
                    self.validationStatus = "Auth Failed: \(code)"
                } else if code == 429 {
                    self.isApiKeyValid = true // Key is valid, just limited
                    self.validationStatus = "Rate Limited (Wait)"
                }
            }
            
            throw NSError(domain: "GeminiService", code: code, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
        
        await MainActor.run {
            self.isApiKeyValid = true
            self.validationStatus = "Valid (Active)"
        }
        
        let completion = try JSONDecoder().decode(GeminiResponse.self, from: data)
        let jsonString = completion.candidates?.first?.content.parts.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? "{}"
        
        // Clean markdown fencing if present (Gemini sometimes adds it despite MimeType)
        let cleanJson = jsonString.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
        
        if let jsonData = cleanJson.data(using: .utf8) {
            return try JSONDecoder().decode(TranslationResult.self, from: jsonData)
        }
        
        return TranslationResult(translatedText: text, fontStyle: "normal")
    }
    // MARK: - AI Story Recap
    
    struct StoryRecapResult: Codable {
        let recap: String
    }
    
    @Published var callCount: Int = 0 // New: Monitor API usage
    
    func generateStoryRecap(series: String, number: String, volume: String, publisher: String) async throws -> String {
        await MainActor.run { self.callCount += 1 }
        
        let urlString = "\(baseURL)?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "GeminiService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Exact Prompt Request from User
        let userPrompt = "Sto iniziano a leggere \(series) #\(number) Vol.\(volume) Casa Editrice \(publisher) , cosa devo sapere per iniziare nel miglior modo"
        print("🤖 GEMINI REQUEST: \(userPrompt)")
        
        let body: [String: Any] = [
            "contents": [
                ["parts": [["text": userPrompt]]]
            ],
            // "generationConfig": ["temperature": 0.7] // Optional: Add strict config if needed
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
             throw NSError(domain: "GeminiService", code: 0, userInfo: [NSLocalizedDescriptionKey: "No Response"])
        }
        
        print("🤖 GEMINI STATUS: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown Error"
            print("🤖 GEMINI ERROR: \(errorMsg)")
            throw NSError(domain: "GeminiService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
        
        let completion = try JSONDecoder().decode(GeminiResponse.self, from: data)
        let text = completion.candidates?.first?.content.parts.first?.text ?? "Non sono riuscito a generare un riassunto."
        
        // Update Valid Status
        await MainActor.run {
            self.isApiKeyValid = true
            self.validationStatus = "Valid (Active)"
        }
        
        return text
    }

    
    
    // MARK: - Vision OCR (Gemini 1.5/2.5 Flash)
    
    enum BalloonShape: String, Codable {
        case oval = "OVAL"
        case rectangle = "RECTANGLE"
        case cloud = "CLOUD"
        case jagged = "JAGGED"
    }
    
    struct BoundingBox: Codable {
        let ymin: Int
        let xmin: Int
        let ymax: Int
        let xmax: Int
        
        // Helper to convert to CGRect for a given image size
        func toCGRect(imageSize: CGSize) -> CGRect {
            let x = CGFloat(xmin) / 1000.0 * imageSize.width
            let y = CGFloat(ymin) / 1000.0 * imageSize.height
            let w = (CGFloat(xmax) - CGFloat(xmin)) / 1000.0 * imageSize.width
            let h = (CGFloat(ymax) - CGFloat(ymin)) / 1000.0 * imageSize.height
            return CGRect(x: x, y: y, width: w, height: h)
        }
    }
    
    struct TranslatedBalloon: Codable, Identifiable {
        let id: String = UUID().uuidString
        let originalText: String
        let translatedText: String
        let should_translate: Bool // v3.1 Logic
        let shape: BalloonShape
        let box2D: [Int] // [ymin, xmin, ymax, xmax]
        let centerPoint: [Int]? // [y, x] - Optional for backward compatibility
        
        var boundingBox: BoundingBox {
            return BoundingBox(ymin: box2D[0], xmin: box2D[1], ymax: box2D[2], xmax: box2D[3])
        }
        
        var center: CGPoint {
            if let cp = centerPoint, cp.count == 2 {
                return CGPoint(x: CGFloat(cp[1]) / 1000.0, y: CGFloat(cp[0]) / 1000.0)
            }
            // Fallback
            let yMid = CGFloat(box2D[0] + box2D[2]) / 2.0 / 1000.0
            let xMid = CGFloat(box2D[1] + box2D[3]) / 2.0 / 1000.0
            return CGPoint(x: xMid, y: yMid)
        }
        
        // Internal use (calculated)
        var localPath: Path? = nil // Legacy/Debug: Full balloon path
        var textMaskPath: Path? = nil // v3.0: Surgical mask for text only
        var backgroundColor: Color = .white
        
        enum CodingKeys: String, CodingKey {
            case originalText = "original_text"
            case translatedText = "italian_translation"
            case should_translate = "should_translate"
            case shape
            case box2D = "box_2d"
            case centerPoint = "center_point"
        }
    }
    
    struct GeminiVisionResponse: Codable {
        let balloons: [TranslatedBalloon]
    }
    
    // MARK: - Helper: Request with Retry
    
    private func performRequestWithRetry(request: URLRequest, maxRetries: Int = 3) async throws -> Data {
        for attempt in 1...maxRetries {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NSError(domain: "GeminiService", code: 0, userInfo: [NSLocalizedDescriptionKey: "No Response"])
                }
                
                if httpResponse.statusCode == 200 {
                    return data
                } else if httpResponse.statusCode == 503 {
                    // Service Unavailable (Overloaded) -> Retry
                    let delay = Double(attempt) * 2.0 // 2s, 4s, 6s...
                    print("🤖 GEMINI OVERLOAD (503). Retrying in \(delay)s (Attempt \(attempt)/\(maxRetries))")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                } else {
                    // Other errors (400, 401, 429, etc) -> Fail immediately
                    let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown Error"
                    print("🤖 GEMINI ERROR: \(errorMsg)")
                    throw NSError(domain: "GeminiService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
                }
                
            } catch {
                // Network errors -> Retry only if it's the last attempt, otherwise throw
                if attempt == maxRetries { throw error }
                print("🤖 GEMINI NETWORK ERROR. Retrying...")
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        throw NSError(domain: "GeminiService", code: 503, userInfo: [NSLocalizedDescriptionKey: "Service Unavailable after retries"])
    }

    func analyzeComicPage(image: UIImage) async throws -> [TranslatedBalloon] {
        await MainActor.run { self.callCount += 1 }
        
        let urlString = "\(baseURL)?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "GeminiService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        // 1. Resize and Compress Image (Standard)
        let maxSize: CGFloat = 1024
        let scale = min(maxSize / image.size.width, maxSize / image.size.height, 1.0)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        
        let resizedImage = UIGraphicsImageRenderer(size: newSize).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        
        guard let imageData = resizedImage.jpegData(compressionQuality: 0.7) else {
            throw NSError(domain: "GeminiService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Image Processing Failed"])
        }
        
        let base64Image = imageData.base64EncodedString()
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 2. Standard "Grid" Prompt (v3.x / v5.0)
        let systemPrompt = """
        Analyze this comic book page with extreme precision.
        Visualize a strict 1000x1000 coordinate grid overlaid on the image (0,0 is top-left, 1000,1000 is bottom-right).
        All spatial measurements must be exact coordinates on this grid.
        
        Detect all speech balloons, captions, and text effects. 
        For each detected item:
        1. Extract the original text.
        2. Determine if it should be translated. Set "should_translate" to FALSE if:
           - It is a Sound Effect (e.g., "THWAP", "BANG", "WHOOSH").
           - It creates the "Ransom Note" effect (single isolated non-words).
           - It is a Proper Name (e.g., "Donavin", "Abbey Chase").
           - It is a Location Name (e.g., "Costa Rica", "New York").
           - It is unintelligible noise.
        3. If "should_translate" is TRUE, provide a natural Italian translation.
        4. Identify the shape (OVAL, RECTANGLE, CLOUD, JAGGED).
        5. Provide the bounding box [ymin, xmin, ymax, xmax] using the 1000x1000 grid.
        6. Provide the precise center point [y, x] of the balloon content using the 1000x1000 grid.

        Output strictly valid JSON obeying this schema:
        {
          "balloons": [
            {
              "original_text": "...",
              "italian_translation": "...",
              "should_translate": true,
              "shape": "OVAL",
              "box_2d": [ymin, xmin, ymax, xmax],
              "center_point": [y, x]
            }
          ]
        }
        """
        
        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": systemPrompt],
                        [
                            "inline_data": [
                                "mime_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.0,
                "responseMimeType": "application/json"
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        print("🤖 GEMINI VISION: Sending Clean Image (v5.0 GrabCut Strategy)...")
        
        let data = try await performRequestWithRetry(request: request)
        
        // Update Valid Status
        await MainActor.run {
            self.isApiKeyValid = true
            self.validationStatus = "Valid (Active)"
        }
        
        let completion = try JSONDecoder().decode(GeminiResponse.self, from: data)
        let jsonString = completion.candidates?.first?.content.parts.first?.text ?? "{}"
        
        await MainActor.run {
            self.lastRawResponse = jsonString // Save for Debug View
            self.lastMarkedImage = nil // Reset marker image as we are sending clean one
        }
        
        if let jsonData = jsonString.data(using: .utf8) {
            let result = try JSONDecoder().decode(GeminiVisionResponse.self, from: jsonData)
            var finalBalloons: [TranslatedBalloon] = []
            
            // v5.0: Post-Process with GrabCut
            // For each valid balloon, use the Gemini Box to seed GrabCut
            
            print("👁️ OpenCV: Starting GrabCut refinement for \(result.balloons.count) items...")
            let processingStart = Date()
            
            for var balloon in result.balloons {
                guard balloon.should_translate else { continue }
                
                // Get Gemini Box (Normalized 0-1)
                // box2D is [ymin, xmin, ymax, xmax] in 1000 grid
                let b = balloon.box2D
                let rect = CGRect(
                    x: CGFloat(b[1]) / 1000.0,
                    y: CGFloat(b[0]) / 1000.0,
                    width: CGFloat(b[3] - b[1]) / 1000.0,
                    height: CGFloat(b[2] - b[0]) / 1000.0
                )
                
                // Call OpenCV GrabCut
                // We pass the ORIGINAl full-res image for best detail? 
                // Or the resized one? 
                // The `image` param passed to this func is likely the full one loaded from disk.
                // GrabCut is slow on huge images.
                // Let's use the `resizedImage` (max 1024) for speed?
                // The Rect is normalized, so it works on any size.
                // But we need the output path to be smooth.
                // Let's use `resizedImage` (already generated above).
                
                let contourPoints = OpenCVWrapper.refinedBalloonContour(resizedImage, textRect: rect)
                
                if let points = contourPoints as? [NSValue], !points.isEmpty {
                    let cgPoints = points.map { $0.cgPointValue }
                    balloon.localPath = Path { p in
                        p.addLines(cgPoints)
                        p.closeSubpath()
                    }
                    print("   - GrabCut success for balloon: \(balloon.originalText.prefix(10))...")
                } else {
                    print("   - GrabCut failed (empty) for balloon: \(balloon.originalText.prefix(10))...")
                }
                
                // Default background
                balloon.backgroundColor = .white
                
                finalBalloons.append(balloon)
            }
            
            print("👁️ OpenCV: GrabCut finished in \(Date().timeIntervalSince(processingStart))s")
            
            return finalBalloons
        }
        
        return []
    }
    
    // MARK: - Persistence
    
    private var translationsDirectory: URL {
        let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = urls[0]
        let translationsDir = appSupport.appendingPathComponent("Translations")
        if !FileManager.default.fileExists(atPath: translationsDir.path) {
            try? FileManager.default.createDirectory(at: translationsDir, withIntermediateDirectories: true)
        }
        return translationsDir
    }
    
    func saveTranslations(_ balloons: [TranslatedBalloon], forBook bookId: String, pageIndex: Int) {
        let filename = "\(bookId)_p\(pageIndex).json"
        let url = translationsDirectory.appendingPathComponent(filename)
        
        do {
            let data = try JSONEncoder().encode(balloons)
            try data.write(to: url)
            print("💾 Saved translations for \(filename)")
        } catch {
            print("⚠️ Failed to save translations: \(error)")
        }
    }
    
    func loadTranslations(forBook bookId: String, pageIndex: Int) -> [TranslatedBalloon]? {
        let filename = "\(bookId)_p\(pageIndex).json"
        let url = translationsDirectory.appendingPathComponent(filename)
        
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        
        do {
            let data = try Data(contentsOf: url)
            let balloons = try JSONDecoder().decode([TranslatedBalloon].self, from: data)
            print("📂 Loaded translations for \(filename)")
            return balloons
        } catch {
            print("⚠️ Failed to load translations: \(error)")
            return nil
        }
    }
}
