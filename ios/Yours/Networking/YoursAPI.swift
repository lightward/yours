import Foundation

enum APIError: Error, Equatable {
    case unauthenticated
    case subscriptionRequired(message: String)
    case divergence(message: String)
    case http(Int)
    case badResponse
}

// The client side of PROTOCOL.md. Stateless except for the bearer token;
// cookies are deliberately disabled — the token is the whole identity story.
final class YoursAPI: @unchecked Sendable {
    var token: String?

    static var baseURL: URL {
        #if DEBUG
        if let override = UserDefaults.standard.string(forKey: "YoursBaseURL"),
           let url = URL(string: override) {
            return url
        }
        return URL(string: "http://localhost:3000")!
        #else
        return URL(string: "https://yours.fyi")!
        #endif
    }

    private let session: URLSession

    init(token: String? = nil) {
        self.token = token
        let configuration = URLSessionConfiguration.default
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Yours-iOS/\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")"
        ]
        session = URLSession(configuration: configuration)
    }

    // MARK: - Endpoints

    func exchangeToken(code: String, verifier: String) async throws -> (token: String, obfuscatedEmail: String?) {
        var request = makeRequest("native/token", method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "code": code,
            "code_verifier": verifier
        ])
        let (data, response) = try await session.data(for: request)
        try Self.check(response, data: data)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = object["token"] as? String
        else { throw APIError.badResponse }
        return (token, object["obfuscated_email"] as? String)
    }

    func state(includeSubscription: Bool = false) async throws -> UniverseState {
        // Query items must go through URLComponents — URL.appending(path:)
        // would percent-encode the "?" into the path and miss the route.
        let query = includeSubscription ? [URLQueryItem(name: "include", value: "subscription")] : []
        let request = makeRequest("native/state", query: query)
        let (data, response) = try await session.data(for: request)
        try Self.check(response, data: data)
        return try YoursJSON.decoder.decode(UniverseState.self, from: data)
    }

    func saveTextarea(_ text: String, universeTime: String) async throws {
        var request = makeRequest("textarea", method: "PUT", universeTime: universeTime)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["textarea": text])
        let (data, response) = try await session.data(for: request)
        try Self.check(response, data: data)
    }

    // POST /stream — opens the SSE stream and returns events as they arrive.
    func stream(message: ChatMessage, universeTime: String) async throws -> AsyncThrowingStream<SSEEvent, Error> {
        var request = makeRequest("stream", method: "POST", universeTime: universeTime)
        request.httpBody = try JSONEncoder().encode(StreamBody(message: message))

        let (bytes, response) = try await session.bytes(for: request)
        if let failure = Self.failure(for: response) {
            // Error bodies are small JSON documents — read them out before throwing
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            throw Self.refine(failure, data: data)
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                var parser = SSELineParser()
                var lineBuffer: [UInt8] = []
                do {
                    for try await byte in bytes {
                        if byte == UInt8(ascii: "\n") {
                            var line = lineBuffer
                            if line.last == UInt8(ascii: "\r") { line.removeLast() }
                            lineBuffer.removeAll(keepingCapacity: true)
                            if let event = parser.consume(line: String(decoding: line, as: UTF8.self)) {
                                continuation.yield(event)
                            }
                        } else {
                            lineBuffer.append(byte)
                        }
                    }
                    if let event = parser.finish() {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func beginSleep() async throws -> String {
        let request = makeRequest("sleep", method: "POST")
        let (data, response) = try await session.data(for: request)
        try Self.check(response, data: data)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let startingTime = object["starting_universe_time"] as? String
        else { throw APIError.badResponse }
        return startingTime
    }

    // POST /native/subscription — hand the server a StoreKit-signed transaction
    // to verify and record. Returns the refreshed state on success.
    func verifySubscription(platform: String, signedTransaction: String) async throws -> UniverseState {
        var request = makeRequest("native/subscription", method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "platform": platform,
            "signed_transaction": signedTransaction
        ])
        let (data, response) = try await session.data(for: request)
        try Self.check(response, data: data)
        return try YoursJSON.decoder.decode(UniverseState.self, from: data)
    }

    func reset() async throws {
        let request = makeRequest("reset", method: "POST")
        let (data, response) = try await session.data(for: request)
        // reset redirects (303) on success; URLSession follows it to / which renders 200
        try Self.check(response, data: data)
    }

    // GET /save — the narrative as plain text, for the share sheet
    func exportText() async throws -> String {
        let request = makeRequest("save")
        let (data, response) = try await session.data(for: request)
        try Self.check(response, data: data)
        guard let text = String(data: data, encoding: .utf8) else { throw APIError.badResponse }
        return text
    }

    // MARK: - Plumbing

    private struct StreamBody: Encodable {
        var message: ChatMessage
    }

    private func makeRequest(_ path: String, method: String = "GET", universeTime: String? = nil, query: [URLQueryItem] = []) -> URLRequest {
        var url = Self.baseURL.appending(path: path)
        if !query.isEmpty {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            components.queryItems = query
            url = components.url!
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let universeTime {
            request.setValue(universeTime, forHTTPHeaderField: "Assert-Yours-Universe-Time")
        }
        return request
    }

    private static func check(_ response: URLResponse, data: Data) throws {
        if let failure = failure(for: response) {
            throw refine(failure, data: data)
        }
    }

    private static func failure(for response: URLResponse) -> APIError? {
        guard let http = response as? HTTPURLResponse else { return .badResponse }
        switch http.statusCode {
        case 200...299: return nil
        case 401: return .unauthenticated
        case 403: return .subscriptionRequired(message: "")
        case 409: return .divergence(message: "")
        default: return .http(http.statusCode)
        }
    }

    // Fills in server-provided messages for the errors that carry them
    private static func refine(_ error: APIError, data: Data) -> APIError {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let message = (object?["message"] as? String) ?? (object?["error"] as? String) ?? ""
        switch error {
        case .subscriptionRequired: return .subscriptionRequired(message: message)
        case .divergence: return .divergence(message: message)
        default: return error
        }
    }
}
