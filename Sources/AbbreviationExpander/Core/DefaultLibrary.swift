import Foundation

/// Unified default abbreviation dictionary library.
public struct DefaultLibrary {
    
    public static var defaultItems: [ExpansionPayload] {
        [
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
    }
}
