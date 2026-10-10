import Foundation

/// Unified default abbreviation dictionary library.
public struct DefaultLibrary {

    public static let hardcodedItems: [ExpansionPayload] = [
        ExpansionPayload(
            id: "gg",
            prefix: "gg",
            expansion: "good game"
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
            id: "eus",
            prefix: "eus",
            expansion: "unamatasanatarai@gmail.com"
        ),
        ExpansionPayload(
            id: ":buu",
            prefix: ":buu",
            expansion: #"rm -rf "$(brew --cache)" ; brew update ; brew upgrade --no-quarantine --cask --greedy ;brew upgrade --no-quarantine --greedy ; brew cleanup --prune=all -s"#
        )
    ]

    public static var defaultItems: [ExpansionPayload] {
        // 1. Try loading from bundled Resources/default-snippets.json
        if let url = Bundle.main.url(forResource: "default-snippets", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let items = try? JSONDecoder().decode([ExpansionPayload].self, from: data),
           !items.isEmpty {
            return items
        }

        // 2. Try loading from direct relative path (useful in dev/test CLI)
        for relPath in ["Resources/default-snippets.json", "../Resources/default-snippets.json"] {
            let fileURL = URL(fileURLWithPath: relPath)
            if let data = try? Data(contentsOf: fileURL),
               let items = try? JSONDecoder().decode([ExpansionPayload].self, from: data),
               !items.isEmpty {
                return items
            }
        }

        // 3. Fallback to identical hardcoded items
        return hardcodedItems
    }
}
