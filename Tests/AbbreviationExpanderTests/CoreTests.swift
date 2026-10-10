import Foundation
import AppKit

public typealias TestRunner = @MainActor (String, () throws -> Void) -> Void

public struct CoreTests {
    @MainActor
    public static func run(testRunner: TestRunner) {

        // MARK: - 1. AppConfig Tests
        testRunner("AppConfig - Properties and Defaults") {
            let initialDelay = AppConfig.popupDelayMs
            AppConfig.popupDelayMs = 250.0
            assert(AppConfig.popupDelayMs == 250.0, "popupDelayMs setter failed")
            AppConfig.popupDelayMs = initialDelay

            let initialWidth = AppConfig.popupWidth
            AppConfig.popupWidth = 300.0
            assert(AppConfig.popupWidth == 300.0, "popupWidth setter failed")
            AppConfig.popupWidth = initialWidth

            let initialHeight = AppConfig.popupMaxHeight
            AppConfig.popupMaxHeight = 200.0
            assert(AppConfig.popupMaxHeight == 200.0, "popupMaxHeight setter failed")
            AppConfig.popupMaxHeight = initialHeight

            let initialRetry = AppConfig.accessibilityRetryInterval
            AppConfig.accessibilityRetryInterval = 3.0
            assert(AppConfig.accessibilityRetryInterval == 3.0, "accessibilityRetryInterval setter failed")
            AppConfig.accessibilityRetryInterval = initialRetry

            assert(AppConfig.appName == "AbbrEx", "appName mismatch")
            assert(AppConfig.bundleIdentifier == "com.citizen.AbbreviationExpander", "bundleIdentifier mismatch")
            assert(AppConfig.version == "1.0.1", "version mismatch")
            assert(!AppConfig.defaultSnippets.isEmpty, "defaultSnippets should not be empty")
        }

        // MARK: - 2. DefaultLibrary Tests
        testRunner("DefaultLibrary - Built-in Items Content & Tags") {
            let items = DefaultLibrary.defaultItems
            assert(items.count == 5, "Expected 5 default items, got \(items.count)")
            assert(items.map(\.prefix) == ["gg", ":shrug", "ty", "eus", ":buu"], "Default prefixes mismatch")
            assert(items[0].expansion == "good game", "gg expansion mismatch")
            assert(items[1].expansion == "¯\\_(ツ)_/¯", ":shrug expansion mismatch")
            assert(items[2].expansion == "Thank you!", "ty expansion mismatch")
            assert(items[3].expansion == "unamatasanatarai@gmail.com", "eus expansion mismatch")
            assert(items[4].expansion == #"rm -rf "$(brew --cache)" ; brew update ; brew upgrade --no-quarantine --cask --greedy ;brew upgrade --no-quarantine --greedy ; brew cleanup --prune=all -s"#, ":buu expansion mismatch")
            for item in items {
                assert(!item.prefix.isEmpty, "Item prefix cannot be empty")
                assert(!item.expansion.isEmpty, "Item expansion cannot be empty")
            }
        }

        // MARK: - 3. Models Tests
        testRunner("Models - ExpansionPayload & EngineState") {
            // ExpansionPayload init with defaults
            let p1 = ExpansionPayload(prefix: "brb", expansion: "be right back")
            assert(!p1.id.isEmpty, "Auto-generated UUID should be non-empty")
            assert(p1.prefix == "brb", "Prefix mismatch")
            assert(p1.expansion == "be right back", "Expansion mismatch")
            assert(p1.tags == nil, "Default tags should be nil")

            // Custom init
            let p2 = ExpansionPayload(id: "custom-id", prefix: "greet", expansion: "hello", tags: ["casual"])
            assert(p2.id == "custom-id", "Custom ID mismatch")
            assert(p2.tags == ["casual"], "Custom tags mismatch")

            // Equatable & Hashable
            assert(p2 == ExpansionPayload(id: "custom-id", prefix: "greet", expansion: "hello", tags: ["casual"]), "Equality failed")
            var set = Set<ExpansionPayload>()
            set.insert(p1)
            set.insert(p2)
            assert(set.count == 2, "Set count mismatch")

            // Codable: Encoding strips ID; decoding generates UUID or parses legacy ID
            let encoder = JSONEncoder()
            let decoder = JSONDecoder()

            let encodedData = try encoder.encode(p2)
            let jsonString = String(data: encodedData, encoding: .utf8)!
            assert(!jsonString.contains("\"id\""), "JSON serialization should omit ID")
            assert(jsonString.contains("greet"), "JSON should contain prefix")
            assert(jsonString.contains("hello"), "JSON should contain expansion")
            assert(jsonString.contains("casual"), "JSON should contain tags")

            // Decoding without ID generates fresh in-memory UUID
            let decodedP2 = try decoder.decode(ExpansionPayload.self, from: encodedData)
            assert(decodedP2.prefix == "greet", "Decoded prefix mismatch")
            assert(decodedP2.expansion == "hello", "Decoded expansion mismatch")
            assert(decodedP2.tags == ["casual"], "Decoded tags mismatch")
            assert(!decodedP2.id.isEmpty, "Decoded item should have generated UUID")

            // Decoding with legacy ID preserves ID
            let legacyJson = """
            {"id": "legacy-123", "prefix": "omg", "expansion": "oh my god"}
            """.data(using: .utf8)!
            let decodedLegacy = try decoder.decode(ExpansionPayload.self, from: legacyJson)
            assert(decodedLegacy.id == "legacy-123", "Legacy ID was not preserved: \(decodedLegacy.id)")
            assert(decodedLegacy.tags == nil, "Tags should be nil")

            // EngineState descriptions
            assert(EngineState.idle.description == "IDLE", "State description mismatch")
            assert(EngineState.buffering.description == "BUFFERING", "State description mismatch")
            assert(EngineState.popupActive.description == "POPUP_ACTIVE", "State description mismatch")
            assert(EngineState.expanded.description == "EXPANDED", "State description mismatch")
            assert(EngineState.cancelled.description == "CANCELLED", "State description mismatch")
        }

        // MARK: - 4. Trie Tests
        testRunner("Trie - Exhaustive Node & Tree Operations") {
            let trie = AbbreviationTrie()

            // Insert empty prefix is guarded
            trie.insert(prefix: "", payload: ExpansionPayload(prefix: "", expansion: ""))
            assert(trie.searchPrefix("").isEmpty, "Empty prefix should return empty results")

            // Normal insertion & case-insensitivity
            let item1 = ExpansionPayload(id: "id-1", prefix: "brb", expansion: "be right back")
            trie.insert(prefix: "BRB", payload: item1)

            let matches = trie.searchPrefix("brb")
            assert(matches.count == 1, "Expected 1 match")
            assert(matches[0].prefix == "brb", "Prefix mismatch")

            // Search with uppercase prefix
            let matchesUpper = trie.searchPrefix("BR")
            assert(matchesUpper.count == 1, "Expected 1 match with uppercase query")

            // Overwrite existing ID under same prefix
            let item1Updated = ExpansionPayload(id: "id-1", prefix: "brb", expansion: "be right back now")
            trie.insert(prefix: "brb", payload: item1Updated)
            assert(trie.searchPrefix("brb").count == 1, "Duplicate ID should replace existing payload")
            assert(trie.searchPrefix("brb").first?.expansion == "be right back now", "Updated payload mismatch")

            // Multiple payloads under same prefix with different IDs
            let item2 = ExpansionPayload(id: "id-2", prefix: "brb", expansion: "bath room break")
            trie.insert(prefix: "brb", payload: item2)
            assert(trie.searchPrefix("brb").count == 2, "Expected 2 payloads under 'brb'")

            // Branching prefixes
            trie.insert(prefix: "break", payload: ExpansionPayload(id: "id-3", prefix: "break", expansion: "take a break"))
            trie.insert(prefix: "bread", payload: ExpansionPayload(id: "id-4", prefix: "bread", expansion: "fresh bread"))

            let bMatches = trie.searchPrefix("br")
            assert(bMatches.count == 4, "Expected 4 items under 'br', got \(bMatches.count)")

            // Max results bound
            let limitedMatches = trie.searchPrefix("br", maxResults: 2)
            assert(limitedMatches.count == 2, "Expected maxResults to cap at 2, got \(limitedMatches.count)")

            // Instant exit on non-matching prefix
            assert(trie.searchPrefix("xyz").isEmpty, "Expected empty result for 'xyz'")
            assert(trie.searchPrefix("brbx").isEmpty, "Expected empty result for non-matching branch")

            // Clear trie
            trie.clear()
            assert(trie.searchPrefix("br").isEmpty, "Trie should be empty after clear()")
            assert(trie.searchPrefix("bread").isEmpty, "Trie should be empty after clear()")
        }

        // MARK: - 5. TemplateEngine Tests
        testRunner("TemplateEngine - Variables, Formats & Fast-Path") {
            // Empty template
            assert(TemplateEngine.evaluate(template: "").text == "", "Empty template failed")

            // Fast-path without tokens
            let plain = "Hello Plain World!"
            assert(TemplateEngine.evaluate(template: plain).text == plain, "Fast path without tokens failed")

            let mockDate = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 14, minute: 30, second: 45))!

            // Date with default format
            let evalDefaultDate = TemplateEngine.evaluate(template: "Today: {{date}}", customDate: mockDate)
            assert(evalDefaultDate.text.contains("Today: "), "Default date evaluation failed")

            // Date with custom format YYYY-MM-DD
            let evalCustomDate1 = TemplateEngine.evaluate(template: "Date: {{date:YYYY-MM-DD}}", customDate: mockDate)
            assert(evalCustomDate1.text == "Date: 2026-10-10", "Date YYYY-MM-DD failed: \(evalCustomDate1.text)")

            // Date with custom format YYYY/MM/DD
            let evalCustomDate2 = TemplateEngine.evaluate(template: "Date: {{date:YYYY/MM/DD}}", customDate: mockDate)
            assert(evalCustomDate2.text == "Date: 2026/10/10", "Date YYYY/MM/DD failed: \(evalCustomDate2.text)")

            // Cache hit test for custom date format
            let evalCustomDateCached = TemplateEngine.evaluate(template: "Date: {{date:YYYY/MM/DD}}", customDate: mockDate)
            assert(evalCustomDateCached.text == "Date: 2026/10/10", "Cached date format failed")

            // Empty format parameter {{date:}} falls back to default
            let evalEmptyFormat = TemplateEngine.evaluate(template: "Date: {{date:}}", customDate: mockDate)
            assert(evalEmptyFormat.text.contains("Date: "), "Empty format parameter failed")

            // Time evaluation
            let evalTime = TemplateEngine.evaluate(template: "Time: {{time}}", customDate: mockDate)
            assert(evalTime.text.contains("Time: 14:30:45"), "Time evaluation failed: \(evalTime.text)")

            // Clipboard custom mock
            let evalClip = TemplateEngine.evaluate(template: "Clip: {{clipboard}}", customClipboard: "SNIPPET_CONTENT")
            assert(evalClip.text == "Clip: SNIPPET_CONTENT", "Clipboard custom mock failed: \(evalClip.text)")

            // Clipboard fallback to general pasteboard
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("PASTEBOARD_TEST", forType: .string)
            let evalClipFallback = TemplateEngine.evaluate(template: "Clip: {{clipboard}}")
            assert(evalClipFallback.text == "Clip: PASTEBOARD_TEST", "Clipboard fallback failed: \(evalClipFallback.text)")

            // Multiple tokens together
            let multi = "Date: {{date:YYYY-MM-DD}} Time: {{time}} Clip: {{clipboard}}"
            let evalMulti = TemplateEngine.evaluate(template: multi, customDate: mockDate, customClipboard: "ABC")
            assert(evalMulti.text == "Date: 2026-10-10 Time: 14:30:45 Clip: ABC", "Multi-token failed: \(evalMulti.text)")
        }

        // MARK: - 6. StateMachine Tests
        testRunner("StateMachine - Full Lifecycle & Boundary Coverage") {
            let trie = AbbreviationTrie()
            let p1 = ExpansionPayload(id: "1", prefix: "brb", expansion: "be right back")
            let p2 = ExpansionPayload(id: "2", prefix: "brt", expansion: "be right there")
            trie.insert(prefix: "brb", payload: p1)
            trie.insert(prefix: "brt", payload: p2)

            let sm = StateMachine(trie: trie)

            var stateNotifications: [(EngineState, [ExpansionPayload], Int)] = []
            sm.onStateChanged = { state, matches, idx in
                stateNotifications.append((state, matches, idx))
            }

            // Initial state
            assert(sm.state == .idle, "Initial state should be IDLE")
            assert(sm.buffer.isEmpty, "Buffer should be empty")

            // Redundant reset on already-idle state returns early
            sm.reset(state: .idle)
            assert(stateNotifications.isEmpty, "Redundant reset should not notify")

            // Load items resets state
            sm.loadItems([p1, p2])
            assert(sm.state == .idle, "State should be IDLE after loadItems")

            // Printable character typing
            sm.processCharacter("b")
            assert(sm.state == .popupActive, "State should be POPUP_ACTIVE")
            assert(sm.activeMatches.count == 2, "Expected 2 active matches for 'b'")

            // Navigation down & up
            sm.navigateSelection(direction: .down)
            assert(sm.selectedIndex == 1, "Selected index should be 1")
            sm.navigateSelection(direction: .down)
            assert(sm.selectedIndex == 0, "Selected index should wrap to 0")
            sm.navigateSelection(direction: .up)
            assert(sm.selectedIndex == 1, "Selected index should wrap to 1 on Up")
            sm.navigateSelection(direction: .up)
            assert(sm.selectedIndex == 0, "Selected index should be 0 on Up")

            // Whitespace resets immediately
            sm.processCharacter(" ")
            assert(sm.state == .idle, "Whitespace should reset state to IDLE")
            assert(sm.buffer.isEmpty, "Buffer should be empty")

            // Newline resets immediately
            sm.processCharacter("b")
            sm.processCharacter("\n")
            assert(sm.state == .idle, "Newline should reset state to IDLE")

            // Buffering state (zero matches)
            sm.processCharacter("z")
            assert(sm.state == .buffering, "State should be BUFFERING")
            assert(sm.activeMatches.isEmpty, "Active matches should be empty")

            // Fast-path: subsequent char when buffering with 0 matches returns early
            sm.processCharacter("q")
            assert(sm.state == .buffering, "State should remain BUFFERING")

            // Backspace operations
            sm.processBackspace() // removes 'q'
            assert(sm.buffer == "z", "Buffer mismatch")
            sm.processBackspace() // removes 'z' -> empty
            assert(sm.state == .idle, "State should reset to IDLE when buffer emptied")

            // Backspace on already empty buffer
            sm.processBackspace()
            assert(sm.state == .idle, "State should remain IDLE")

            // Expand candidate at index
            sm.processCharacter("b")
            sm.processCharacter("r")
            sm.processCharacter("b")
            assert(sm.state == .popupActive, "State should be POPUP_ACTIVE")
            assert(sm.activeMatches.count == 1, "Expected 1 match for 'brb'")

            // Expand out of bounds index returns nil
            assert(sm.processSelectionToExpand(index: 99) == nil, "Out of bounds index should return nil")
            assert(sm.processSelectionToExpand(index: -1) == nil, "Negative index should return nil")

            // Successful expansion
            let expansion = sm.processSelectionToExpand()
            assert(expansion != nil, "Expansion should succeed")
            assert(expansion?.payload.prefix == "brb", "Prefix mismatch")
            assert(expansion?.prefixLength == 3, "Prefix length mismatch")
            assert(expansion?.evaluated.text == "be right back", "Evaluated text mismatch")
            assert(sm.state == .idle, "State should be IDLE after expansion")

            // Expanding when not active returns nil
            assert(sm.processSelectionToExpand() == nil, "Expanding in IDLE state should return nil")

            // Navigate when not active does nothing
            sm.navigateSelection(direction: .down)
            assert(sm.selectedIndex == 0, "Navigation should be no-op when IDLE")

            // Cancel
            sm.processCharacter("b")
            sm.cancel()
            assert(sm.state == .cancelled, "State should be CANCELLED")
        }

        // MARK: - 7. LibraryStorage Tests
        testRunner("LibraryStorage - File Operations, Recovery & Directory Creation") {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AbbrExTests_\(UUID().uuidString)")
            let testFileURL = tempDir.appendingPathComponent("nested/folder/test_library.json")
            let storage = LibraryStorage(fileURL: testFileURL)

            // Save creates intermediate directories
            let testItems = [ExpansionPayload(id: "test-1", prefix: "sig", expansion: "Best regards")]
            try storage.save(items: testItems)
            assert(FileManager.default.fileExists(atPath: testFileURL.path), "File should exist after save")

            // Load reads correctly
            let loaded = storage.load()
            assert(loaded.count == 1, "Expected 1 loaded item")
            assert(loaded[0].prefix == "sig", "Prefix mismatch")

            // Corrupted file recovery: writes corrupted bytes, load falls back to defaults
            try "INVALID_JSON_CORRUPTED".data(using: .utf8)!.write(to: testFileURL)
            let fallbackItems = storage.load()
            assert(!fallbackItems.isEmpty, "Corrupted file should recover to default snippets")

            // Remove file
            try storage.removeStorageFile()
            assert(!FileManager.default.fileExists(atPath: testFileURL.path), "File should be removed")

            // Remove non-existent file is safe
            try storage.removeStorageFile()

            // Clean up test directory
            try? FileManager.default.removeItem(at: tempDir)
        }

        // MARK: - 8. CaretTracker Tests
        testRunner("CaretTracker - Geometry & Screen Boundary Flipping") {
            let screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
            let visibleFrame = CGRect(x: 0, y: 24, width: 1920, height: 1032)

            // 1. Normal caret in center of screen (not flipped)
            let normalCaret = CaretTracker.CaretRect(
                origin: CGPoint(x: 500, y: 500),
                height: 20,
                isFlippedAbove: false,
                isFlippedLeft: false,
                screenFrame: screenFrame,
                visibleFrame: visibleFrame
            )
            let originNormal = CaretTracker.calculateAnchoredOrigin(for: normalCaret, panelWidth: 240, panelHeight: 150)
            assert(originNormal.x >= visibleFrame.minX && originNormal.x + 240 <= visibleFrame.maxX, "Normal X out of bounds")
            assert(originNormal.y >= visibleFrame.minY && originNormal.y + 150 <= visibleFrame.maxY, "Normal Y out of bounds")

            // 2. Caret flipped above (near bottom of screen)
            let flippedAboveCaret = CaretTracker.CaretRect(
                origin: CGPoint(x: 500, y: 1000),
                height: 20,
                isFlippedAbove: true,
                isFlippedLeft: false,
                screenFrame: screenFrame,
                visibleFrame: visibleFrame
            )
            let originFlippedAbove = CaretTracker.calculateAnchoredOrigin(for: flippedAboveCaret, panelWidth: 240, panelHeight: 150)
            assert(originFlippedAbove.y >= visibleFrame.minY, "Flipped above Y out of bounds")

            // 3. Caret flipped left (near right edge of screen)
            let flippedLeftCaret = CaretTracker.CaretRect(
                origin: CGPoint(x: 1850, y: 500),
                height: 20,
                isFlippedAbove: false,
                isFlippedLeft: true,
                screenFrame: screenFrame,
                visibleFrame: visibleFrame
            )
            let originFlippedLeft = CaretTracker.calculateAnchoredOrigin(for: flippedLeftCaret, panelWidth: 240, panelHeight: 150)
            assert(originFlippedLeft.x + 240 <= visibleFrame.maxX, "Flipped left X out of bounds")

            // 4. Clamping left & top boundaries
            let edgeCaret = CaretTracker.CaretRect(
                origin: CGPoint(x: -50, y: -50),
                height: 20,
                isFlippedAbove: false,
                isFlippedLeft: false,
                screenFrame: screenFrame,
                visibleFrame: visibleFrame
            )
            let originEdge = CaretTracker.calculateAnchoredOrigin(for: edgeCaret, panelWidth: 240, panelHeight: 150)
            assert(originEdge.x >= visibleFrame.minX, "Clamped X below minimum")
            assert(originEdge.y <= visibleFrame.maxY - 150, "Clamped Y above maximum")

            // getCaretScreenPosition fallback
            let fallbackRect = CaretTracker.getCaretScreenPosition(popupWidth: 240, popupHeight: 150)
            assert(fallbackRect.height > 0, "Fallback caret rect height should be positive")
        }

        // MARK: - 9. TextReplacer Tests
        testRunner("TextReplacer - Flag Management & Replacer Invocation") {
            assert(!TextReplacer.isReplacing, "Initial isReplacing should be false")
            TextReplacer.isReplacing = true
            assert(TextReplacer.isReplacing, "isReplacing flag setter failed")
            TextReplacer.isReplacing = false

            // Replace invocation handles non-empty and empty text safely without crashing
            TextReplacer.replace(prefixLength: 0, evaluated: EvaluatedTemplate(text: ""))
            assert(TextReplacer.isReplacing, "isReplacing should be true during replacement execution")

            // Verify deferred reset
            let deadline = Date().addingTimeInterval(0.3)
            while TextReplacer.isReplacing && Date() < deadline {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            }
            assert(!TextReplacer.isReplacing, "isReplacing should reset to false after deferred duration")
        }
    }
}
