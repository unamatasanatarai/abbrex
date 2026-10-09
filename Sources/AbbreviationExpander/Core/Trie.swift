import Foundation

/// Node within the Abbreviation Trie.
public final class TrieNode {
    public var children: [Character: TrieNode] = [:]
    public var payloads: [ExpansionPayload] = []
    public var isEndOfWord: Bool = false

    public init() {}
}

/// Bounded O(k) Trie (Prefix Tree) Data Structure for ultra-fast abbreviation prefix matching.
public final class AbbreviationTrie {
    private let root = TrieNode()

    public init() {}

    /// Inserts an abbreviation and its expansion payload into the Trie.
    /// Prefix matching is case-insensitive.
    public func insert(prefix: String, payload: ExpansionPayload) {
        guard !prefix.isEmpty else { return }
        let normalized = prefix.lowercased()
        var current = root

        for char in normalized {
            if let nextNode = current.children[char] {
                current = nextNode
            } else {
                let newNode = TrieNode()
                current.children[char] = newNode
                current = newNode
            }
        }

        current.isEndOfWord = true
        // Avoid duplicate payloads with identical ID
        if let idx = current.payloads.firstIndex(where: { $0.id == payload.id }) {
            current.payloads[idx] = payload
        } else {
            current.payloads.append(payload)
        }
    }

    /// Searches candidate expansion matches starting with the specified prefix.
    /// Time complexity: O(k + m) where k is prefix length and m is number of collected candidate matches.
    /// Returns empty array in < 1ms if prefix not found.
    public func searchPrefix(_ prefix: String) -> [ExpansionPayload] {
        guard !prefix.isEmpty else { return [] }
        let normalized = prefix.lowercased()
        var current = root

        for char in normalized {
            guard let nextNode = current.children[char] else {
                return [] // Instant exit when prefix does not match
            }
            current = nextNode
        }

        var results: [ExpansionPayload] = []
        collectSubtree(current, results: &results)
        return results
    }

    private func collectSubtree(_ node: TrieNode, results: inout [ExpansionPayload]) {
        if node.isEndOfWord && !node.payloads.isEmpty {
            results.append(contentsOf: node.payloads)
        }
        for childNode in node.children.values {
            collectSubtree(childNode, results: &results)
        }
    }

    /// Resets the Trie structure.
    public func clear() {
        root.children.removeAll()
        root.payloads.removeAll()
        root.isEndOfWord = false
    }
}
