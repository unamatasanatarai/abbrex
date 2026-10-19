import Foundation
import CoreGraphics

/// Centralized Configuration Management for Abbreviation Expander Application.
public struct AppConfig {

    // MARK: - UI & Overlay Popout Settings

    /// Default delay in milliseconds before displaying candidate suggestions popout window (300ms).
    public static let defaultPopupDelayMs: Double = 300.0

    private static let popupDelayKey = "AppConfig.popupDelayMs"
    public static var userDefaults: UserDefaults = .standard

    /// Delay in milliseconds before displaying candidate suggestions popout window.
    public static var popupDelayMs: Double {
        get {
            if userDefaults.object(forKey: popupDelayKey) != nil {
                return userDefaults.double(forKey: popupDelayKey)
            }
            return defaultPopupDelayMs
        }
        set {
            userDefaults.set(newValue, forKey: popupDelayKey)
        }
    }

    /// Resets the popup delay setting to its default value (300ms).
    public static func resetPopupDelayToDefault() {
        userDefaults.removeObject(forKey: popupDelayKey)
    }

    /// Default width of the floating overlay candidate panel.
    public static var popupWidth: CGFloat = 240.0

    /// Maximum height of the floating overlay candidate panel.
    public static var popupMaxHeight: CGFloat = 150.0

    // MARK: - Application Metadata

    public static let appName: String = "AbbrEx"
    public static let bundleIdentifier: String = "com.citizen.AbbreviationExpander"
    public static var version: String {
        // 1. Bundle info dictionary (when running inside compiled .app bundle)
        if let bundleVer = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String, !bundleVer.isEmpty {
            return bundleVer
        }
        // 2. Bundled resource file
        if let url = Bundle.main.url(forResource: "VERSION", withExtension: nil),
           let str = try? String(contentsOf: url, encoding: .utf8) {
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        // 3. Root or relative VERSION file (tests, dev CLI)
        for relPath in ["VERSION", "../VERSION", "Resources/VERSION"] {
            if let str = try? String(contentsOfFile: relPath, encoding: .utf8) {
                let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return "1.0.2"
    }

    // MARK: - Engine & Monitoring Settings

    /// Interval in seconds to check/retry Accessibility permission event tap.
    public static var accessibilityRetryInterval: Double = 2.0

    // MARK: - Default Snippet Library

    /// Built-in preset abbreviation payloads for Copywriters and QA Engineers.
    public static var defaultSnippets: [ExpansionPayload] {
        return DefaultLibrary.defaultItems
    }
}
