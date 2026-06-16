import Foundation

// GET /native/state — everything the client needs to render itself.
// See PROTOCOL.md.
struct UniverseState: Decodable, Equatable {
    var universeDay: Int
    var universeTime: String
    var narrative: [ChatMessage]
    var textarea: String?
    var obfuscatedEmail: String?
    var subscriptionActive: Bool
    var subscription: SubscriptionDetails?
    // Set as StoreKit's appAccountToken at purchase so the server can bind the
    // transaction to this account (cross-account replay prevention).
    var iapAccountToken: String?

    // The "1 day" / "day 2" pun, preserved (uses a non-breaking space like
    // the web's universe_day_with_units)
    var dayWithUnits: String {
        universeDay == 1 ? "1\u{00A0}day" : "day\u{00A0}\(universeDay)"
    }

    static func dayWithUnits(_ day: Int) -> String {
        day == 1 ? "1\u{00A0}day" : "day\u{00A0}\(day)"
    }
}

struct SubscriptionDetails: Decodable, Equatable {
    var status: String
    var cancelAtPeriodEnd: Bool
    var currentPeriodEnd: Date?
    var amount: Int
    var currency: String
    var interval: String
}

// One entry in the narrative, in the Lightward AI chat_log shape:
// { role:, content: [{ type: "text", text: }] }
struct ChatMessage: Codable, Equatable {
    var role: String
    var content: [ContentBlock]

    struct ContentBlock: Codable, Equatable {
        var type: String
        var text: String
    }

    var text: String {
        content.map(\.text).joined(separator: "\n")
    }

    static func user(_ text: String) -> ChatMessage {
        ChatMessage(role: "user", content: [ContentBlock(type: "text", text: text)])
    }
}

enum YoursJSON {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            let withFractional = ISO8601DateFormatter()
            withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFractional.date(from: string) { return date }
            let plain = ISO8601DateFormatter()
            if let date = plain.date(from: string) { return date }
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unrecognized date: \(string)"
            ))
        }
        return decoder
    }()
}
