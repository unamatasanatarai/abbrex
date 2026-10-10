import Foundation
import CoreGraphics

/// Centralized Configuration Management for Abbreviation Expander Application.
public struct AppConfig {

    // MARK: - UI & Overlay Popout Settings

    /// Delay in milliseconds before displaying candidate suggestions popout window (e.g. 200ms).
    public static var popupDelayMs: Double = 200.0

    /// Default width of the floating overlay candidate panel.
    public static var popupWidth: CGFloat = 240.0

    /// Maximum height of the floating overlay candidate panel.
    public static var popupMaxHeight: CGFloat = 150.0

    // MARK: - Application Metadata

    public static let appName: String = "AbbrEx"
    public static let bundleIdentifier: String = "com.citizen.AbbreviationExpander"
    public static let version: String = "1.0.1"

    // MARK: - Engine & Monitoring Settings

    /// Interval in seconds to check/retry Accessibility permission event tap.
    public static var accessibilityRetryInterval: Double = 2.0

    // MARK: - Default Snippet Library

    /// Built-in preset abbreviation payloads for Copywriters and QA Engineers.
    public static var defaultSnippets: [ExpansionPayload] {
        return DefaultLibrary.defaultItems
    }
}
