import Foundation
import AppKit

/// Result of evaluating an expansion template.
public struct EvaluatedTemplate {
    public let text: String
    public let cursorOffset: Int?

    public init(text: String, cursorOffset: Int?) {
        self.text = text
        self.cursorOffset = cursorOffset
    }
}

/// Dynamic variable parsing engine (evaluates {{date}}, {{time}}, {{clipboard}}, {{cursor}}).
public final class TemplateEngine {
    
    /// Evaluates dynamic variables in a template string.
    /// - Parameters:
    ///   - template: Raw expansion string containing tokens like {{date}}, {{clipboard}}
    ///   - customDate: Optional date for deterministic testing
    ///   - customClipboard: Optional clipboard string for deterministic testing
    /// - Returns: EvaluatedTemplate containing final string and optional cursor offset
    public static func evaluate(template: String, customDate: Date? = nil, customClipboard: String? = nil) -> EvaluatedTemplate {
        guard !template.isEmpty else {
            return EvaluatedTemplate(text: "", cursorOffset: nil)
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

        // 4. Evaluate {{cursor}} placement marker
        var cursorOffset: Int? = nil
        if let cursorRange = text.range(of: "{{cursor}}") {
            let distance = text.distance(from: text.startIndex, to: cursorRange.lowerBound)
            cursorOffset = distance
            text = text.replacingOccurrences(of: "{{cursor}}", with: "")
        }

        return EvaluatedTemplate(text: text, cursorOffset: cursorOffset)
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
        } else {
            formatter.dateFormat = "yyyy-MM-dd"
        }

        return formatter.string(from: date)
    }
}
