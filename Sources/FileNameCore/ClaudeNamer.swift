import Foundation

enum NamingError: LocalizedError {
    case engineUnavailable(String)
    case badResponse(String)

    var errorDescription: String? {
        switch self {
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

    struct Request: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }
        // No sampling parameters: current Claude models (Sonnet 5 and later)
        // reject non-default `temperature` with HTTP 400.
        let model: String
        let max_tokens: Int
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

    /// Falls back to the default model when the Settings field is empty or
    /// whitespace, and strips stray whitespace a paste can bring along.
    static func resolvedModel(_ model: String) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? PrefKey.defaultClaudeModel : trimmed
    }

    static func suggestName(from extraction: PDFExtraction, apiKey: String, model: String, includeDate: Bool) async throws -> String {
        let body = Request(
            model: resolvedModel(model),
            max_tokens: 200,
            system: NamingPrompt.rules(includeDate: includeDate),
            messages: [Request.Message(role: "user", content: NamingPrompt.userPrompt(for: extraction, excerptLimit: 3500))]
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
            model: resolvedModel(model),
            max_tokens: 8,
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
        // A pasted key can carry a trailing newline; a newline in a header
        // value makes the request fail outright.
        request.setValue(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "x-api-key")
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
