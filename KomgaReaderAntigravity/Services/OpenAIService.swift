import Foundation
import Combine

class OpenAIService: ObservableObject {
    static let shared = OpenAIService()
    
    @Published var isApiKeyValid: Bool = false
    @Published var validationStatus: String = "Checking..."
    
    private var apiKey: String {
        return UserDefaults.standard.string(forKey: "openAiApiKey") ?? ""
    }
    private let baseURL = URL(string: AppConstants.openAIBaseURL)!
    
    private init() {
        Task {
            await verifyApiKey()
        }
    }
    
    func verifyApiKey() async {
        guard !apiKey.isEmpty && apiKey != "YOUR_OPENAI_API_KEY_HERE" else {
            await MainActor.run {
                self.isApiKeyValid = false
                self.validationStatus = "Missing API Key"
            }
            return
        }
        
        // Simple check: Try to list models or just make a very cheap request
        // Since we only have chat completion setup, let's try a minimal chat request
        // Or we can use the models endpoint if we want to be cleaner, but let's stick to what we have.
        // Actually, let's use a dedicated URLRequest for models to be safe and cheap.
        
        let modelsURL = URL(string: "https://api.openai.com/v1/models")!
        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                await MainActor.run {
                    self.isApiKeyValid = true
                    self.validationStatus = "API Key Valid"
                }
            } else {
                await MainActor.run {
                    self.isApiKeyValid = false
                    self.validationStatus = "Invalid API Key"
                }
            }
        } catch {
            await MainActor.run {
                self.isApiKeyValid = false
                self.validationStatus = "Connection Error"
            }
        }
    }
    
    struct ChatCompletionRequest: Codable {
        let model: String
        let messages: [Message]
        let temperature: Double
        
        struct Message: Codable {
            let role: String
            let content: String
        }
    }
    
    struct ChatCompletionResponse: Codable {
        let choices: [Choice]
        
        struct Choice: Codable {
            let message: ChatCompletionRequest.Message
        }
    }
    
    func translate(text: String, context: String = "", to targetLanguage: String = "Italian") async throws -> String {
        guard isApiKeyValid else {
            // Re-check if it was just missing initially
            if apiKey != "YOUR_OPENAI_API_KEY_HERE" && !apiKey.isEmpty {
                 // Try anyway? No, trust the validation or re-verify.
            }
             throw NSError(domain: "OpenAIService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Invalid or Missing OpenAI API Key. Status: \(validationStatus)"])
        }
        
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let systemPrompt = """
        You are an expert comic book translator specializing in localization from American English to Italian.
        Your goal is to translate the text into natural, spoken Italian, maintaining the original tone, slang, and character voice.
        
        Rules:
        1. Source is American English (often containing slang, idioms, or street talk).
        2. Target is Italian. Use informal, slang-heavy Italian where appropriate for the context.
        3. Keep the translation CONCISE to fit inside small speech bubbles. Shorten sentences if possible without losing meaning.
        4. If the text is a sound effect (e.g., "BOOM", "POW", "BLAM"), adapt it to standard Italian comic sound effects or keep it if universal.
        5. Maintain consistency with the provided context.
        6. Output ONLY the translated text. No explanations, no quotes.
        """
        
        let userPrompt = """
        Context so far:
        \(context)
        
        Text to translate:
        "\(text)"
        """
        
        let bodyObj = ChatCompletionRequest(
            model: AppConstants.openAIModel,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userPrompt)
            ],
            temperature: 0.7 // Slightly creative for slang
        )
        
        request.httpBody = try JSONEncoder().encode(bodyObj)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "OpenAIService", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
        
        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        return completion.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? text
    }
}
