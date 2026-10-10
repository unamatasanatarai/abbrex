import Foundation
import AppKit

/// Result of evaluating an expansion template.
public struct EvaluatedTemplate {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

/// Dynamic variable parsing engine (evaluates {{date}}, {{time}}, {{clipboard}}).
public final class TemplateEngine {

    private static let dateRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"\{\{date(?::([^}]+))?\}\}"#,
        options: []
    )

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let defaultDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static var customFormattersLock = os_unfair_lock()
    private static var customFormattersCache: [String: DateFormatter] = [:]

    /// Evaluates dynamic variables in a template string.
    /// - Parameters:
    ///   - template: Raw expansion string containing tokens like {{date}}, {{time}}, {{clipboard}}
    ///   - customDate: Optional date for deterministic testing
    ///   - customClipboard: Optional clipboard string for deterministic testing
    /// - Returns: EvaluatedTemplate containing final string
    public static func evaluate(template: String, customDate: Date? = nil, customClipboard: String? = nil) -> EvaluatedTemplate {
        guard !template.isEmpty else {
            return EvaluatedTemplate(text: "")
        }

        // Fast-path: If template contains no variables, return text immediately with zero allocations
        guard template.contains("{{") else {
            return EvaluatedTemplate(text: template)
        }

        let now = customDate ?? Date()
        var text = template

        // 1. Evaluate {{date}} or {{date:FORMAT}}
        if text.contains("{{date"), let regex = dateRegex {
            let nsString = text as NSString
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length)).reversed()

            for match in matches {
                var formatStr: String? = nil
                if match.numberOfRanges > 1 && match.range(at: 1).location != NSNotFound {
                    formatStr = nsString.substring(with: match.range(at: 1))
                }
                let formattedDate = formatDate(now, format: formatStr)
                let range = match.range
                text = (text as NSString).replacingCharacters(in: range, with: formattedDate)
            }
        }

        // 2. Evaluate {{time}}
        if text.contains("{{time}}") {
            let timeStr = timeFormatter.string(from: now)
            text = text.replacingOccurrences(of: "{{time}}", with: timeStr)
        }

        // 3. Evaluate {{clipboard}}
        if text.contains("{{clipboard}}") {
            let clipText: String
            if let customClipboard = customClipboard {
                clipText = customClipboard
            } else {
                clipText = NSPasteboard.general.string(forType: .string) ?? ""
            }
            text = text.replacingOccurrences(of: "{{clipboard}}", with: clipText)
        }

        return EvaluatedTemplate(text: text)
    }

    /// Formats a Date using standard tokens or cached DateFormatter
    private static func formatDate(_ date: Date, format: String?) -> String {
        guard let format = format, !format.isEmpty else {
            return defaultDateFormatter.string(from: date)
        }

        os_unfair_lock_lock(&customFormattersLock)
        let cached = customFormattersCache[format]
        os_unfair_lock_unlock(&customFormattersLock)

        if let cached = cached {
            return cached.string(from: date)
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale.current
        let swiftFormat = format
            .replacingOccurrences(of: "YYYY", with: "yyyy")
            .replacingOccurrences(of: "DD", with: "dd")
        formatter.dateFormat = swiftFormat

        os_unfair_lock_lock(&customFormattersLock)
        customFormattersCache[format] = formatter
        os_unfair_lock_unlock(&customFormattersLock)

        return formatter.string(from: date)
    }
}
