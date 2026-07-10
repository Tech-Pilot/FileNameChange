import Foundation

enum NamingError: LocalizedError {
    case noAPIKey
    case engineUnavailable(String)
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No Claude API key set."
        case .engineUnavailable(let reason):
            return reason
        case .badResponse(let message):
            return message
        }
    }
}

/// Names PDFs by sending a text excerpt to the Anthropic Messages API.
enum ClaudeNamer {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    static let systemPrompt = """
    You name PDF files based on their content. Reply with ONLY a file name base — no extension, no quotes, no explanations, nothing else.

    Rules:
    - 3 to 10 words that say what the document is: its type, subject, and who it involves.
    - If the document has one clearly primary date (invoice date, statement date, letter date), start with it as YYYY-MM-DD followed by a space.
    - Include the company, institution, or person the document is about when that helps identify it.
    - Use Title Case with normal spaces. Never use slashes, colons, quotes, or periods.
    - Write the name in the document's own language.
    """

    struct Request: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }
        let model: String
        let max_tokens: Int
        let temperature: Double
        let system: String
        let messages: [Message]
    }

    struct Response: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }
        let content: [Block]
    }

    struct APIErrorResponse: Decodable {
        struct Detail: Decodable {
            let type: String?
            let message: String?
        }
        let error: Detail?
    }

    static func suggestName(from extraction: PDFExtraction, apiKey: String, model: String) async throws -> String {
        let excerpt = String(extraction.text.prefix(3500))
        var prompt = "Current file name: \(extraction.fileName).pdf\n"
        if let title = extraction.metadataTitle, !title.isEmpty {
            prompt += "PDF metadata title: \(title)\n"
        }
        prompt += "\nDocument text (first pages):\n\(excerpt)"
        if excerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prompt += "\n(No text could be extracted from this PDF.)"
        }

        let body = Request(
            model: model.isEmpty ? PrefKey.defaultClaudeModel : model,
            max_tokens: 200,
            temperature: 0.2,
            system: systemPrompt,
            messages: [Request.Message(role: "user", content: prompt)]
        )

        let text = try await send(body: body, apiKey: apiKey)
        let cleaned = FilenameSanitizer.cleanAISuggestion(text)
        guard !cleaned.isEmpty else {
            throw NamingError.badResponse("Claude returned an empty name.")
        }
        return cleaned
    }

    /// Tiny round-trip used by the "Verify" button in Settings.
    static func verify(apiKey: String, model: String) async throws {
        let body = Request(
            model: model.isEmpty ? PrefKey.defaultClaudeModel : model,
            max_tokens: 8,
            temperature: 0,
            system: "Reply with OK.",
            messages: [Request.Message(role: "user", content: "OK?")]
        )
        _ = try await send(body: body, apiKey: apiKey)
    }

    private static func send(body: Request, apiKey: String) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard statusCode == 200 else {
            if let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data),
               let message = apiError.error?.message {
                if statusCode == 401 {
                    throw NamingError.badResponse("Claude rejected the API key — check it in Settings.")
                }
                throw NamingError.badResponse("Claude error: \(message)")
            }
            throw NamingError.badResponse("Claude request failed (HTTP \(statusCode)).")
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let text = decoded.content.first(where: { $0.type == "text" })?.text,
              !text.isEmpty else {
            throw NamingError.badResponse("Claude returned no text.")
        }
        return text
    }
}
