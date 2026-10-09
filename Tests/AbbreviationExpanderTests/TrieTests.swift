import XCTest
@testable import AbbreviationExpander

final class TrieTests: XCTestCase {
    func testInsertAndSearchPrefix() {
        let trie = AbbreviationTrie()
        let item = ExpansionPayload(id: "1", prefix: "brb", title: "Be Right Back", expansion: "be right back", category: "copywriter")
        trie.insert(prefix: "brb", payload: item)

        let matches = trie.searchPrefix("brb")
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.title, "Be Right Back")
    }

    func testPartialPrefixMatch() {
        let trie = AbbreviationTrie()
        trie.insert(prefix: "qa-bug", payload: ExpansionPayload(id: "1", prefix: "qa-bug", title: "QA Bug Report", expansion: "Bug details...", category: "qa"))
        trie.insert(prefix: "qa-env", payload: ExpansionPayload(id: "2", prefix: "qa-env", title: "QA Environment", expansion: "Env specs...", category: "qa"))

        let matches = trie.searchPrefix("qa")
        XCTAssertEqual(matches.count, 2)
    }

    func testNonMatchingPrefixInstantExit() {
        let trie = AbbreviationTrie()
        trie.insert(prefix: "disclaimer", payload: ExpansionPayload(id: "1", prefix: "disclaimer", title: "Legal Disclaimer", expansion: "Terms...", category: "copywriter"))

        let start = CFAbsoluteTimeGetCurrent()
        let matches = trie.searchPrefix("xyz")
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000.0

        XCTAssertTrue(matches.isEmpty)
        XCTAssertLessThan(elapsedMs, 1.0)
    }

    func testCaseInsensitiveSearch() {
        let trie = AbbreviationTrie()
        trie.insert(prefix: "FYI", payload: ExpansionPayload(id: "1", prefix: "FYI", title: "For Your Info", expansion: "FYI text", category: "copywriter"))

        let matchesLower = trie.searchPrefix("fyi")
        let matchesUpper = trie.searchPrefix("FYI")
        XCTAssertEqual(matchesLower.count, 1)
        XCTAssertEqual(matchesUpper.count, 1)
    }

    func testRemoveAndClear() {
        let trie = AbbreviationTrie()
        trie.insert(prefix: "faq", payload: ExpansionPayload(id: "1", prefix: "faq", title: "FAQ", expansion: "Frequently Asked Questions", category: "copywriter"))

        XCTAssertEqual(trie.searchPrefix("faq").count, 1)
        let removed = trie.remove(prefix: "faq", id: "1")
        XCTAssertTrue(removed)
        XCTAssertEqual(trie.searchPrefix("faq").count, 0)

        trie.insert(prefix: "a", payload: ExpansionPayload(id: "2", prefix: "a", title: "A", expansion: "Alpha", category: "gen"))
        trie.clear()
        XCTAssertEqual(trie.getAll().count, 0)
    }
}
