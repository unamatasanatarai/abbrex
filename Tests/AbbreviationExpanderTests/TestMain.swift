import Foundation

@main
struct TestMain {
    static func main() {
        print("==================================================")
        print("  Running Abbreviation Expander Native Test Suite  ")
        print("==================================================")

        var passed = 0
        var failed = 0

        func runTest(_ name: String, block: () throws -> Void) {
            do {
                try block()
                print("  ✔ PASS: \(name)")
                passed += 1
            } catch {
                print("  ❌ FAIL: \(name) - \(error)")
                failed += 1
            }
        }

        // 1. Trie Tests
        runTest("Trie - Insert & Search Exact Prefix") {
            let trie = AbbreviationTrie()
            let item = ExpansionPayload(id: "1", prefix: "brb", expansion: "be right back")
            trie.insert(prefix: "brb", payload: item)

            let matches = trie.searchPrefix("brb")
            assert(matches.count == 1, "Expected 1 match")
            assert(matches.first?.prefix == "brb", "Prefix mismatch")
        }

        runTest("Trie - O(k) Partial Prefix Search") {
            let trie = AbbreviationTrie()
            trie.insert(prefix: "qa-bug", payload: ExpansionPayload(id: "1", prefix: "qa-bug", expansion: "Bug details..."))
            trie.insert(prefix: "qa-env", payload: ExpansionPayload(id: "2", prefix: "qa-env", expansion: "Env specs..."))

            let matches = trie.searchPrefix("qa")
            assert(matches.count == 2, "Expected 2 candidate matches")
        }

        runTest("Trie - Instant exit on non-matching prefix (< 1ms)") {
            let trie = AbbreviationTrie()
            trie.insert(prefix: "disclaimer", payload: ExpansionPayload(id: "1", prefix: "disclaimer", expansion: "Terms..."))

            let start = CFAbsoluteTimeGetCurrent()
            let matches = trie.searchPrefix("xyz")
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000.0

            assert(matches.isEmpty, "Expected empty matches")
            assert(elapsedMs < 1.0, "Lookup execution took \(elapsedMs)ms")
        }

        runTest("DefaultLibrary - Initialization & Unified Library Items") {
            let items = DefaultLibrary.defaultItems
            assert(!items.isEmpty, "Library should contain default items")
            assert(items.contains(where: { $0.prefix.contains("disc") }), "Should contain disc prefix")
            assert(items.contains(where: { $0.prefix == "qa-bug" }), "Should contain qa-bug")
        }

        // 2. Template Engine Tests
        runTest("TemplateEngine - Date, Time & Clipboard Token Parsing") {
            let date = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 9))!
            let template = "Date: {{date:YYYY/MM/DD}}, Clip: {{clipboard}}"

            let evaluated = TemplateEngine.evaluate(template: template, customDate: date, customClipboard: "MOCK_CLIP")

            assert(evaluated.text == "Date: 2026/10/09, Clip: MOCK_CLIP", "Text output mismatch: \(evaluated.text)")
        }

        // 3. State Machine & Keystroke Buffer Tests
        runTest("StateMachine - Lifecycle & State Transitions") {
            let trie = AbbreviationTrie()
            let payload = ExpansionPayload(id: "1", prefix: "brb", expansion: "be right back")
            trie.insert(prefix: "brb", payload: payload)

            let sm = StateMachine(trie: trie)

            sm.processCharacter("b")
            assert(sm.state == .popupActive, "State should be POPUP_ACTIVE")
            assert(sm.activeMatches.count == 1, "Expected 1 active match")

            sm.processCharacter("x") // "bx" has 0 matches
            assert(sm.state == .buffering, "State should be BUFFERING")
            assert(sm.activeMatches.count == 0, "Expected 0 matches")

            sm.processBackspace() // back to "b"
            assert(sm.state == .popupActive, "State should be POPUP_ACTIVE")

            let expansion = sm.processSelectionToExpand()
            assert(expansion != nil, "Expansion should not be nil")
            assert(expansion?.payload.prefix == "brb", "Prefix mismatch")
            assert(sm.state == .idle, "State should reset to IDLE")
        }

        // 4. Persistence & Storage Tests
        runTest("LibraryStorage - First Launch Default Initialization") {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let testFileURL = tempDir.appendingPathComponent("test_library.json")
            let storage = LibraryStorage(fileURL: testFileURL)

            // File does not exist yet
            assert(!FileManager.default.fileExists(atPath: testFileURL.path), "File should not exist yet")

            // Load should return defaults and create the initial file
            let items = storage.load()
            assert(!items.isEmpty, "Default items should not be empty")
            assert(FileManager.default.fileExists(atPath: testFileURL.path), "File should have been created on disk")

            // Clean up
            try? storage.removeStorageFile()
            try? FileManager.default.removeItem(at: tempDir)
        }

        runTest("LibraryStorage - Edit Preservation Across Opens") {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let testFileURL = tempDir.appendingPathComponent("test_library.json")
            let storage1 = LibraryStorage(fileURL: testFileURL)

            // Start with custom items
            let customItem1 = ExpansionPayload(id: "custom-1", prefix: "myemail", expansion: "user@example.com")
            let customItem2 = ExpansionPayload(id: "custom-2", prefix: "greet", expansion: "Hello World!")
            try storage1.save(items: [customItem1, customItem2])

            // Simulate quitting the app and opening it again (new storage instance loading from disk)
            let storage2 = LibraryStorage(fileURL: testFileURL)
            let loaded = storage2.load()

            assert(loaded.count == 2, "Expected 2 items loaded, got \(loaded.count)")
            assert(loaded[0].prefix == "myemail", "First item prefix mismatch")
            assert(loaded[0].expansion == "user@example.com", "First item expansion mismatch")
            assert(loaded[1].prefix == "greet", "Second item prefix mismatch")

            // Simulate updating an item and reloading
            let updatedItem = ExpansionPayload(id: "custom-1", prefix: "myemail", expansion: "user@updated.com")
            try storage2.save(items: [updatedItem, customItem2])

            let storage3 = LibraryStorage(fileURL: testFileURL)
            let reloaded = storage3.load()
            assert(reloaded.first(where: { $0.id == "custom-1" })?.expansion == "user@updated.com", "Updated item was not preserved")

            // Clean up
            try? storage3.removeStorageFile()
            try? FileManager.default.removeItem(at: tempDir)
        }

        runTest("LibraryStorage - Empty Library Preserved Across Opens") {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let testFileURL = tempDir.appendingPathComponent("test_library.json")
            let storage1 = LibraryStorage(fileURL: testFileURL)

            // User clears all snippets
            try storage1.save(items: [])

            // Next open
            let storage2 = LibraryStorage(fileURL: testFileURL)
            let loaded = storage2.load()
            assert(loaded.isEmpty, "Empty library should be preserved, not reverted to defaults")

            // Clean up
            try? storage2.removeStorageFile()
            try? FileManager.default.removeItem(at: tempDir)
        }

        print("--------------------------------------------------")
        print("  Summary: \(passed) Passed | \(failed) Failed")
        print("==================================================")

        if failed > 0 {
            exit(1)
        }
    }
}
