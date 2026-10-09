import XCTest
@testable import AbbreviationExpander

final class EngineTests: XCTestCase {
    
    func testTemplateEngineDateAndClipboard() {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 9))!
        let template = "Date: {{date:YYYY/MM/DD}}, Clip: {{clipboard}}"

        let evaluated = TemplateEngine.evaluate(template: template, customDate: date, customClipboard: "MOCK_CLIP")

        XCTAssertEqual(evaluated.text, "Date: 2026/10/09, Clip: MOCK_CLIP")
    }

    func testStateMachineTransitions() {
        let trie = AbbreviationTrie()
        let payload = ExpansionPayload(id: "1", prefix: "brb", title: "Be Right Back", expansion: "be right back", category: "copywriter")
        trie.insert(prefix: "brb", payload: payload)

        let sm = StateMachine(trie: trie)

        sm.processCharacter("b")
        XCTAssertEqual(sm.state, .popupActive)
        XCTAssertEqual(sm.activeMatches.count, 1)

        sm.processCharacter("r")
        XCTAssertEqual(sm.state, .popupActive)

        sm.processCharacter("x") // "brx" matches nothing
        XCTAssertEqual(sm.state, .buffering)
        XCTAssertEqual(sm.activeMatches.count, 0)

        sm.processBackspace() // back to "br"
        XCTAssertEqual(sm.state, .popupActive)
        XCTAssertEqual(sm.activeMatches.count, 1)

        let expansion = sm.processTabToExpand()
        XCTAssertNotNil(expansion)
        XCTAssertEqual(expansion?.payload.prefix, "brb")
        XCTAssertEqual(sm.state, .idle)
    }
}
