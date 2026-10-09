import Foundation

/// Represents an abbreviation expansion item payload.
public struct ExpansionPayload: Codable, Identifiable, Hashable, Equatable {
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

/// Core state machine states.
public enum EngineState: String, CustomStringConvertible {
    case idle = "IDLE"
    case buffering = "BUFFERING"
    case popupActive = "POPUP_ACTIVE"
    case expanded = "EXPANDED"
    case cancelled = "CANCELLED"

    public var description: String { rawValue }
}
