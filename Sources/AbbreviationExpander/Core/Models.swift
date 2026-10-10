import Foundation

/// Represents an abbreviation expansion item payload.
public struct ExpansionPayload: Identifiable, Hashable, Equatable {
    public let id: String
    public let prefix: String
    public let expansion: String
    public let tags: [String]?

    public init(id: String = UUID().uuidString, prefix: String, expansion: String, tags: [String]? = nil) {
        self.id = id
        self.prefix = prefix
        self.expansion = expansion
        self.tags = tags
    }
}

extension ExpansionPayload: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case prefix
        case expansion
        case tags
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // If an id exists in legacy JSON, read it; otherwise generate an in-memory UUID
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.prefix = try container.decode(String.self, forKey: .prefix)
        self.expansion = try container.decode(String.self, forKey: .expansion)
        self.tags = try container.decodeIfPresent([String].self, forKey: .tags)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Omit id completely from JSON serialization (purely in-memory runtime identity)
        try container.encode(prefix, forKey: .prefix)
        try container.encode(expansion, forKey: .expansion)
        if let tags = tags, !tags.isEmpty {
            try container.encode(tags, forKey: .tags)
        }
    }
}

/// Core state machine states.
public enum EngineState: String, CustomStringConvertible {
    case idle = "IDLE"
    case buffering = "BUFFERING"
    case popupActive = "POPUP_ACTIVE"
    case expanded = "EXPANDED"
    case cancelled = "CANCELLED"

    public var description: String { rawValue }
}
