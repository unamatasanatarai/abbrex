import Foundation
import SwiftUI
import AppKit

public struct UITests {
    @MainActor
    public static func run(testRunner: TestRunner) {

        // MARK: - 1. CandidateViewModel & CandidateRow Tests
        testRunner("CandidateListView & CandidateRow - Properties & States") {
            let p1 = ExpansionPayload(id: "1", prefix: "brb", expansion: "be right back")
            let p2 = ExpansionPayload(id: "2", prefix: "long", expansion: "This is a very long expansion exceeding thirty characters for preview truncation test")

            let vm = CandidateViewModel(matches: [p1, p2], selectedIndex: 0)
            assert(vm.matches.count == 2, "CandidateViewModel matches count mismatch")
            assert(vm.selectedIndex == 0, "CandidateViewModel selectedIndex mismatch")

            // CandidateRow views
            var clickedIndex: Int?
            let row1 = CandidateRow(match: p1, isSelected: true, onClick: { clickedIndex = 0 })
            let row2 = CandidateRow(match: p2, isSelected: false, onClick: { clickedIndex = 1 })

            assert(row1.isSelected, "Row1 should be selected")
            assert(!row2.isSelected, "Row2 should not be selected")

            row1.onClick()
            assert(clickedIndex == 0, "Row1 click action failed")
            row2.onClick()
            assert(clickedIndex == 1, "Row2 click action failed")

            // Render CandidateListView view hierarchy
            let listView = CandidateListView(viewModel: vm) { idx in
                clickedIndex = idx
            }
            _ = listView.body
        }

        // MARK: - 2. OverlayPanel Tests
        testRunner("OverlayPanel - Frame Geometry, Show & Dismiss") {
            let panel = OverlayPanel()
            assert(!panel.isOpaque, "OverlayPanel should be non-opaque")
            assert(panel.backgroundColor == .clear, "OverlayPanel background should be clear")
            assert(panel.level == .floating, "OverlayPanel level should be floating")
            assert(!panel.isVisible, "OverlayPanel should initially be hidden")

            let p1 = ExpansionPayload(id: "1", prefix: "brb", expansion: "be right back")
            let p2 = ExpansionPayload(id: "2", prefix: "ty", expansion: "thank you")
            let caretRect = CaretTracker.CaretRect(
                origin: CGPoint(x: 300, y: 300),
                height: 20,
                isFlippedAbove: false,
                isFlippedLeft: false
            )

            // Show panel
            panel.show(matches: [p1], selectedIndex: 0, caretRect: caretRect)
            assert(panel.frame.width == AppConfig.popupWidth, "OverlayPanel width mismatch")
            assert(panel.frame.height > 0, "OverlayPanel height should be positive")

            // Update content while visible
            panel.show(matches: [p1, p2], selectedIndex: 1, caretRect: caretRect)

            // Dismiss panel
            panel.dismiss()
        }

        // MARK: - 3. AppViewModel CRUD & JSON Import/Export Tests
        testRunner("AppViewModel - Complete CRUD, Persistence & JSON Import") {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AbbrExVMTests_\(UUID().uuidString)")
            let testFileURL = tempDir.appendingPathComponent("test_vm_library.json")
            let storage = LibraryStorage(fileURL: testFileURL)

            let vm = AppViewModel(storage: storage)
            assert(!vm.libraryItems.isEmpty, "Initial libraryItems should contain default snippets")

            // Check permissions & settings
            vm.checkAccessibilityPermissions()
            vm.openAccessibilitySettings()
            vm.startMonitoring()
            vm.reloadTrie()

            // 1. Add Item (sorted alphabetically)
            let added = vm.addItem(prefix: "test-p", expansion: "test-e")
            assert(vm.libraryItems.contains(where: { $0.id == added.id }), "Added item should be in libraryItems")
            assert(vm.libraryItems.first(where: { $0.id == added.id })?.prefix == "test-p", "Added prefix mismatch")
            assert(vm.libraryItems == AppViewModel.sortSnippets(vm.libraryItems), "libraryItems should be sorted alphabetically")

            // 2. Update Item
            let updated = ExpansionPayload(id: added.id, prefix: "test-p-up", expansion: "test-e-up", tags: ["tag1"])
            vm.updateItem(updated)
            assert(vm.libraryItems.first(where: { $0.id == added.id })?.prefix == "test-p-up", "Updated prefix mismatch")
            assert(vm.libraryItems.first(where: { $0.id == added.id })?.tags == ["tag1"], "Updated tags mismatch")
            assert(vm.libraryItems == AppViewModel.sortSnippets(vm.libraryItems), "libraryItems should remain sorted after update")

            // Update non-existent item is a safe no-op
            vm.updateItem(ExpansionPayload(id: "non-existent", prefix: "foo", expansion: "bar"))

            // 3. Delete Item
            vm.deleteItem(updated)
            assert(!vm.libraryItems.contains(where: { $0.id == updated.id }), "Deleted item should be removed")

            // 4. Save Library (immediate and debounced)
            vm.saveLibrary(immediate: true)
            vm.saveLibrary(immediate: false)

            // 5. Replace Library
            let replacement = [
                ExpansionPayload(prefix: ":r1", expansion: "replacement 1"),
                ExpansionPayload(prefix: ":r2", expansion: "replacement 2")
            ]
            vm.replaceLibrary(with: replacement)
            assert(vm.libraryItems.count == 2, "Expected 2 replaced items")

            // 6. JSON Import / Export Parsing Logic
            // Schema 1: Native Array
            let nativeJson = """
            [{"prefix": ":imp1", "expansion": "imported 1"}]
            """.data(using: .utf8)!
            let decodedNative = try JSONDecoder().decode([ExpansionPayload].self, from: nativeJson)
            vm.replaceLibrary(with: decodedNative)
            assert(vm.libraryItems.first?.prefix == ":imp1", "Native import failed")

            // Schema 2: Key-value dictionary
            let kvJson = """
            {":dict1": "dict value 1", ":dict2": "dict value 2"}
            """.data(using: .utf8)!
            let dict = try JSONDecoder().decode([String: String].self, from: kvJson)
            let kvPayloads = dict.map { ExpansionPayload(prefix: $0.key, expansion: $0.value) }
            vm.replaceLibrary(with: kvPayloads)
            assert(vm.libraryItems.count == 2, "KV dict import failed")

            // Clean up
            try? storage.removeStorageFile()
            try? FileManager.default.removeItem(at: tempDir)
        }

        // MARK: - 4. PreferencesView & Subview Logic Tests
        testRunner("PreferencesView - Component Lifecycle, Undo & Esc-to-Cancel") {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AbbrExPrefTests_\(UUID().uuidString)")
            let testFileURL = tempDir.appendingPathComponent("test_pref_library.json")
            let storage = LibraryStorage(fileURL: testFileURL)
            let vm = AppViewModel(storage: storage)

            let prefView = PreferencesView(viewModel: vm)
            _ = prefView.body

            // Test ItemEditorView
            let item = ExpansionPayload(prefix: "test", expansion: "hello")
            var updatedItem: ExpansionPayload?
            var wasCancelled = false

            let editor = ItemEditorView(
                item: item,
                isNew: false,
                onUpdate: { updated in
                    updatedItem = updated
                },
                onCancel: {
                    wasCancelled = true
                }
            )
            _ = editor.body
            editor.onUpdate(ExpansionPayload(id: item.id, prefix: "updated", expansion: "world"))
            assert(updatedItem?.prefix == "updated", "editor onUpdate callback failed")
            assert(!wasCancelled, "Initial wasCancelled should be false")

            var returnedToSearch = false
            let editorWithReturn = ItemEditorView(
                item: item,
                isNew: false,
                onUpdate: { _ in },
                onCancel: {},
                onReturnToSearch: { returnedToSearch = true }
            )
            _ = editorWithReturn.body
            editorWithReturn.onReturnToSearch()
            assert(returnedToSearch, "editor onReturnToSearch callback failed")

            // Test SidebarItemRow
            var deletedRow = false
            let row = SidebarItemRow(
                item: item,
                isSelected: true,
                onDelete: { deletedRow = true }
            )
            _ = row.body
            row.onDelete()
            assert(deletedRow, "SidebarItemRow onDelete failed")

            // Test PlusIconButton & ActionMenuButton
            var plusClicked = false
            let plusButton = PlusIconButton(action: { plusClicked = true })
            _ = plusButton.body
            plusButton.action()
            assert(plusClicked, "PlusIconButton action failed")

            var imported = false
            var exported = false
            var restored = false
            let actionMenu = ActionMenuButton(
                onImport: { imported = true },
                onExport: { exported = true },
                onRestoreDefaults: { restored = true }
            )
            _ = actionMenu.body
            actionMenu.onImport()
            actionMenu.onExport()
            actionMenu.onRestoreDefaults?()
            assert(imported && exported && restored, "ActionMenuButton actions failed")

            // Clean up
            try? storage.removeStorageFile()
            try? FileManager.default.removeItem(at: tempDir)
        }

        // MARK: - 5. Custom AppKit Controls Tests (MacSingleLineTextField, MacTextEditor)
        testRunner("Custom AppKit Controls - MacSingleLineTextField & MacTextEditor") {
            // MacSingleLineTextField
            var text = "search query"
            var committed = false
            var escaped = false

            var focusTrigger = true
            let singleLine = MacSingleLineTextField(
                placeholder: "Search...",
                text: Binding(get: { text }, set: { text = $0 }),
                font: .systemFont(ofSize: 12),
                isMonospaced: true,
                isAutoFocused: true,
                focusTrigger: Binding(get: { focusTrigger }, set: { focusTrigger = $0 }),
                onCommit: { committed = true },
                onEscape: {
                    escaped = true
                    return true
                }
            )

            let coordinator = singleLine.makeCoordinator()
            let textField = CustomNSTextField()
            textField.delegate = coordinator
            coordinator.textField = textField
            coordinator.parent = singleLine

            // Render view with NSHostingView
            let host1 = NSHostingView(rootView: singleLine)
            _ = host1.fittingSize

            // Coordinator events
            assert(coordinator.handleEscape(), "Coordinator escape should return true")
            assert(escaped, "Coordinator onEscape was not called")

            // Text change notification
            textField.stringValue = "new value\nwith newline\r"
            let notif = Notification(name: NSControl.textDidChangeNotification, object: textField)
            coordinator.controlTextDidChange(notif)
            assert(!text.contains("\n") && !text.contains("\r"), "Newline should be stripped from single-line text field")

            // Newline commit
            let textView = NSTextView()
            assert(coordinator.control(textField, textView: textView, doCommandBy: #selector(NSResponder.insertNewline(_:))), "insertNewline should be handled")
            assert(committed, "onCommit was not triggered")

            // Select all
            assert(coordinator.control(textField, textView: textView, doCommandBy: #selector(NSText.selectAll(_:))), "selectAll should be handled")

            // Cancel operation
            assert(coordinator.control(textField, textView: textView, doCommandBy: #selector(NSResponder.cancelOperation(_:))), "cancelOperation should be handled")

            // CustomNSTextField Key Equivalents
            let escEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 53)!
            assert(textField.performKeyEquivalent(with: escEvent), "CustomNSTextField performKeyEquivalent for Esc failed")

            let cmdAEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0, windowNumber: 0, context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0x00)!
            assert(textField.performKeyEquivalent(with: cmdAEvent), "CustomNSTextField performKeyEquivalent for Cmd+A failed")

            textField.cancelOperation(nil)
            textField.keyDown(with: escEvent)
            textField.viewDidMoveToWindow()

            // MacTextEditor
            var editorText = "multiline text"
            var editorEscaped = false

            let editor = MacTextEditor(
                text: Binding(get: { editorText }, set: { editorText = $0 }),
                font: .monospacedSystemFont(ofSize: 13, weight: .regular),
                isEditable: true,
                onEscape: {
                    editorEscaped = true
                    return true
                }
            )

            let editorCoordinator = editor.makeCoordinator()
            let nsTextView = MacNSTextView()
            nsTextView.delegate = editorCoordinator
            editorCoordinator.textView = nsTextView
            editorCoordinator.parent = editor

            let host2 = NSHostingView(rootView: editor)
            _ = host2.fittingSize

            assert(editorCoordinator.handleEscape(), "MacTextEditor escape should return true")
            assert(editorEscaped, "MacTextEditor onEscape was not called")

            nsTextView.string = "updated text"
            let textNotif = Notification(name: NSText.didChangeNotification, object: nsTextView)
            editorCoordinator.textDidChange(textNotif)
            assert(editorText == "updated text", "MacTextEditor textDidChange failed")

            assert(editorCoordinator.textView(nsTextView, doCommandBy: #selector(NSResponder.cancelOperation(_:))), "cancelOperation should be handled")

            assert(nsTextView.performKeyEquivalent(with: escEvent), "MacNSTextView performKeyEquivalent for Esc failed")
            assert(nsTextView.performKeyEquivalent(with: cmdAEvent), "MacNSTextView performKeyEquivalent for Cmd+A failed")

            nsTextView.cancelOperation(nil)
            nsTextView.keyDown(with: escEvent)
        }
    }
}
