import Foundation
import AppKit
import CoreGraphics
import Carbon

public struct ServiceTests {
    @MainActor
    public static func run(testRunner: TestRunner) {

        testRunner("EventMonitor - Lifecycle, CGEvent & NSEvent Dispatch") {
            let trie = AbbreviationTrie()
            let p1 = ExpansionPayload(id: "test-1", prefix: "brb", expansion: "be right back")
            trie.insert(prefix: "brb", payload: p1)

            let sm = StateMachine(trie: trie)
            let monitor = EventMonitor(stateMachine: sm)

            // 1. Lifecycle start and stop
            monitor.start()
            monitor.stop()

            // 2. TextReplacer.isReplacing guard
            TextReplacer.isReplacing = true
            let dummyEvent = CGEvent(source: nil)!
            let replacedIgnored = monitor.handleCGEvent(dummyEvent, type: .keyDown)
            assert(!replacedIgnored, "Keystroke should be ignored when TextReplacer is active")
            TextReplacer.isReplacing = false

            // 2b. Secure Input Gating (passwords, PINs, master keys)
            sm.processCharacter("b")
            assert(sm.state == .popupActive, "State should be POPUP_ACTIVE")
            EnableSecureEventInput()
            let secureIgnored = monitor.handleCGEvent(dummyEvent, type: .keyDown)
            assert(!secureIgnored, "Keystroke should return false when secure event input is enabled")
            assert(sm.state == .idle, "State should be reset to IDLE when secure input is enabled")
            DisableSecureEventInput()

            // 3. Mouse Click Handling (leftMouseDown)
            // Left click when state is idle
            assert(!monitor.handleCGEvent(dummyEvent, type: .leftMouseDown), "Left click in idle state should return false")

            // Left click when state is popupActive
            sm.processCharacter("b")
            assert(sm.state == .popupActive, "State should be POPUP_ACTIVE")
            _ = monitor.handleCGEvent(dummyEvent, type: .leftMouseDown)

            // Let async reset execute
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            assert(sm.state == .idle, "Mouse click outside should reset state to IDLE")

            // 4. Modifier Flags Handling
            // Command key press resets state
            sm.processCharacter("b")
            assert(sm.state == .popupActive)
            let cmdEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0x00, keyDown: true)!
            cmdEvent.flags = .maskCommand
            assert(!monitor.handleCGEvent(cmdEvent, type: .keyDown), "Cmd key event should return false")
            assert(sm.state == .idle, "Cmd key should reset state machine")

            // Option key press resets state
            sm.processCharacter("b")
            let optEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0x00, keyDown: true)!
            optEvent.flags = .maskAlternate
            assert(!monitor.handleCGEvent(optEvent, type: .keyDown), "Option key event should return false")
            assert(sm.state == .idle, "Option key should reset state machine")

            // 5. KeyCode: Escape (0x35)
            sm.processCharacter("b")
            let escEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0x35, keyDown: true)!
            escEvent.flags = []
            assert(!monitor.handleCGEvent(escEvent, type: .keyDown), "Escape should return false")
            assert(sm.state == .cancelled, "Escape should cancel state machine")

            // 6. KeyCode: Backspace (0x33)
            sm.reset(state: .idle)
            sm.processCharacter("b")
            let backspaceEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0x33, keyDown: true)!
            backspaceEvent.flags = []
            assert(!monitor.handleCGEvent(backspaceEvent, type: .keyDown), "Backspace should return false")
            assert(sm.state == .idle, "Backspace should empty buffer and reset to IDLE")

            // 7. KeyCode: Tab (0x30) & Enter (0x24) Expansion Commit
            sm.reset(state: .idle)
            sm.processCharacter("b")
            sm.processCharacter("r")
            sm.processCharacter("b")
            assert(sm.state == .popupActive)
            let tabEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0x30, keyDown: true)!
            tabEvent.flags = []
            let tabConsumed = monitor.handleCGEvent(tabEvent, type: .keyDown)
            assert(tabConsumed, "Tab on active popup should consume event (return true)")
            assert(sm.state == .idle, "State should be IDLE after expansion")
            TextReplacer.isReplacing = false

            // Enter on non-active state returns false
            let enterEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0x24, keyDown: true)!
            enterEvent.flags = []
            assert(!monitor.handleCGEvent(enterEvent, type: .keyDown), "Enter on idle should return false")

            // 8. Arrow Keys Navigation: Up (0x7E) & Down (0x7D)
            sm.reset(state: .idle)
            sm.processCharacter("b")
            let downEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0x7D, keyDown: true)!
            downEvent.flags = []
            assert(monitor.handleCGEvent(downEvent, type: .keyDown), "Down arrow on active popup should consume event")
            let upEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0x7E, keyDown: true)!
            upEvent.flags = []
            assert(monitor.handleCGEvent(upEvent, type: .keyDown), "Up arrow on active popup should consume event")

            // Left arrow (0x7B) & Right arrow (0x7C) reset state
            let leftEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0x7B, keyDown: true)!
            leftEvent.flags = []
            assert(!monitor.handleCGEvent(leftEvent, type: .keyDown), "Left arrow should return false")
            assert(sm.state == .idle, "Left arrow should reset state machine")

            sm.processCharacter("b")
            let rightEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0x7C, keyDown: true)!
            rightEvent.flags = []
            assert(!monitor.handleCGEvent(rightEvent, type: .keyDown), "Right arrow should return false")
            assert(sm.state == .idle, "Right arrow should reset state machine")

            // 9. Spacebar (0x31)
            sm.processCharacter("b")
            let spaceEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0x31, keyDown: true)!
            spaceEvent.flags = []
            assert(!monitor.handleCGEvent(spaceEvent, type: .keyDown), "Spacebar should return false")
            assert(sm.state == .idle, "Spacebar should reset state machine")

            // 10. Function Keys (0x60..0x79)
            sm.processCharacter("b")
            let f1Event = CGEvent(keyboardEventSource: nil, virtualKey: 0x60, keyDown: true)!
            f1Event.flags = []
            assert(!monitor.handleCGEvent(f1Event, type: .keyDown), "F1 should return false")
            assert(sm.state == .idle, "F1 should reset state machine")

            // 11. Control Key Navigation & Shortcuts
            sm.reset(state: .idle)
            sm.processCharacter("b")

            // Ctrl+j (0x26) -> Down
            let ctrlJ = CGEvent(keyboardEventSource: nil, virtualKey: 0x26, keyDown: true)!
            ctrlJ.flags = .maskControl
            assert(monitor.handleCGEvent(ctrlJ, type: .keyDown), "Ctrl+j should consume event")

            // Ctrl+k (0x28) -> Up
            let ctrlK = CGEvent(keyboardEventSource: nil, virtualKey: 0x28, keyDown: true)!
            ctrlK.flags = .maskControl
            assert(monitor.handleCGEvent(ctrlK, type: .keyDown), "Ctrl+k should consume event")

            // Ctrl+n (0x2D) -> Down
            let ctrlN = CGEvent(keyboardEventSource: nil, virtualKey: 0x2D, keyDown: true)!
            ctrlN.flags = .maskControl
            assert(monitor.handleCGEvent(ctrlN, type: .keyDown), "Ctrl+n should consume event")

            // Ctrl+p (0x23) -> Up
            let ctrlP = CGEvent(keyboardEventSource: nil, virtualKey: 0x23, keyDown: true)!
            ctrlP.flags = .maskControl
            assert(monitor.handleCGEvent(ctrlP, type: .keyDown), "Ctrl+p should consume event")

            // Ctrl+l (0x25) -> Expand
            let ctrlL = CGEvent(keyboardEventSource: nil, virtualKey: 0x25, keyDown: true)!
            ctrlL.flags = .maskControl
            assert(monitor.handleCGEvent(ctrlL, type: .keyDown), "Ctrl+l should consume and expand")
            assert(sm.state == .idle, "State should be IDLE after Ctrl+l expansion")
            TextReplacer.isReplacing = false

            // Other Ctrl key when idle
            let otherCtrl = CGEvent(keyboardEventSource: nil, virtualKey: 0x00, keyDown: true)!
            otherCtrl.flags = .maskControl
            assert(!monitor.handleCGEvent(otherCtrl, type: .keyDown), "Other Ctrl key should return false")

            // 12. handleNSEvent fallback
            if let nsEvent = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "b",
                charactersIgnoringModifiers: "b",
                isARepeat: false,
                keyCode: 0x0B
            ) {
                assert(!monitor.handleNSEvent(nsEvent), "NSEvent fallback should route without crashing")
            }
        }
    }
}
