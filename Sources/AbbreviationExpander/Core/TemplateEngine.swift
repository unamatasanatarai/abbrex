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

        let now = customDate ?? Date()
        var text = template

        // 1. Evaluate {{date}} or {{date:FORMAT}}
        let datePattern = #"\{\{date(?::([^}]+))?\}\}"#
        if let regex = try? NSRegularExpression(pattern: datePattern, options: []) {
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
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timeStr = formatter.string(from: now)
        text = text.replacingOccurrences(of: "{{time}}", with: timeStr)

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

    /// Formats a Date using standard tokens or DateFormatter
    public static func formatDate(_ date: Date, format: String?) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale.current

        if let format = format, !format.isEmpty {
            let swiftFormat = format
                .replacingOccurrences(of: "YYYY", with: "yyyy")
                .replacingOccurrences(of: "DD", with: "dd")
            formatter.dateFormat = swiftFormat
            return formatter.string(from: date)
        }

        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
