import Foundation

/// Unified default abbreviation dictionary library.
public struct DefaultLibrary {

    public static let hardcodedItems: [ExpansionPayload] = [
        ExpansionPayload(
            id: ":buu",
            prefix: ":buu",
            expansion: "brew update ; brew upgrade --cask --greedy ;brew upgrade --greedy ; brew cleanup --prune=all -s"
        ),
        ExpansionPayload(
            id: ":shrug",
            prefix: ":shrug",
            expansion: "¯\\_(ツ)_/¯"
        ),
        ExpansionPayload(
            id: "ty",
            prefix: "ty",
            expansion: "Thank you!"
        ),
        ExpansionPayload(
            id: "wtf",
            prefix: "wtf",
            expansion: "Well... Shave my legs and paint me blue!"
        )
    ]

    public static var defaultItems: [ExpansionPayload] {
        var items: [ExpansionPayload]? = nil

        // 1. Try loading from bundled Resources/default-snippets.json
        if let url = Bundle.main.url(forResource: "default-snippets", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([ExpansionPayload].self, from: data),
           !decoded.isEmpty {
            items = decoded
        }

        // 2. Try loading from direct relative path (useful in dev/test CLI)
        if items == nil {
            for relPath in ["Resources/default-snippets.json", "../Resources/default-snippets.json"] {
                let fileURL = URL(fileURLWithPath: relPath)
                if let data = try? Data(contentsOf: fileURL),
                   let decoded = try? JSONDecoder().decode([ExpansionPayload].self, from: data),
                   !decoded.isEmpty {
                    items = decoded
                    break
                }
            }
        }

        let result = items ?? hardcodedItems
        return result.sorted { $0.prefix.localizedCaseInsensitiveCompare($1.prefix) == .orderedAscending }
    }
}
