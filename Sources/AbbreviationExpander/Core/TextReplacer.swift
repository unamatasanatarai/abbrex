import Foundation
import AppKit
import CoreGraphics
import ApplicationServices

/// Text Replacement Engine using AXUIElement Accessibility APIs with CGEvent fallback.
public final class TextReplacer {

    private static let systemWide = AXUIElementCreateSystemWide()
    private static let hidSource = CGEventSource(stateID: .hidSystemState)

    private static var isReplacingLock = os_unfair_lock()
    private static var _isReplacing: Bool = false

    /// Guard flag: when true, event monitor ignores all keystrokes to prevent catching synthetic replacement events.
    public static var isReplacing: Bool {
        get {
            os_unfair_lock_lock(&isReplacingLock)
            defer { os_unfair_lock_unlock(&isReplacingLock) }
            return _isReplacing
        }
        set {
            os_unfair_lock_lock(&isReplacingLock)
            _isReplacing = newValue
            os_unfair_lock_unlock(&isReplacingLock)
        }
    }

    /// Replaces the typed abbreviation prefix with expanded template content.
    /// - Parameters:
    ///   - prefixLength: Number of characters typed in abbreviation to backspace/delete.
    ///   - evaluated: Evaluated template text content.
    public static func replace(prefixLength: Int, evaluated: EvaluatedTemplate) {
        isReplacing = true

        // Strategy A: Try Native macOS Accessibility API replacement (Fast, precise, zero clipboard side-effects)
        if replaceViaAccessibility(prefixLength: prefixLength, evaluated: evaluated) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isReplacing = false
            }
            return
        }

        // Strategy B: Fallback to simulated Backspaces + NSPasteboard Cmd+V
        // Executed asynchronously on a background userInteractive queue to avoid blocking
        // the caller (such as the CGEventTap callback thread) with synchronous sleeps.
        DispatchQueue.global(qos: .userInteractive).async {
            replaceViaKeystrokeSimulation(prefixLength: prefixLength, evaluated: evaluated)
        }
    }

    /// Strategy A: Replaces text directly using macOS AXUIElement Accessibility API.
    private static func replaceViaAccessibility(prefixLength: Int, evaluated: EvaluatedTemplate) -> Bool {
        var focusedElementVal: CFTypeRef?

        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElementVal) == .success,
              let focusedElement = focusedElementVal else {
            return false
        }

        let axElement = focusedElement as! AXUIElement

        // 1. Get current text range / selection
        var selectedRangeVal: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axElement, kAXSelectedTextRangeAttribute as CFString, &selectedRangeVal) == .success,
              let rangeVal = selectedRangeVal else {
            return false
        }

        var currentRange = CFRange()
        guard AXValueGetValue(rangeVal as! AXValue, .cfRange, &currentRange) else {
            return false
        }

        // 2. Compute range covering the typed abbreviation prefix
        let deleteLocation = max(0, currentRange.location - prefixLength)
        let deleteLength = min(prefixLength + currentRange.length, currentRange.location + currentRange.length)
        var replaceRange = CFRange(location: deleteLocation, length: deleteLength)

        guard let targetRangeValue = AXValueCreate(.cfRange, &replaceRange) else {
            return false
        }

        // 3. Set text selection range to highlight the typed prefix
        guard AXUIElementSetAttributeValue(axElement, kAXSelectedTextRangeAttribute as CFString, targetRangeValue) == .success else {
            return false
        }

        // 4. Replace selected range with expansion content
        guard AXUIElementSetAttributeValue(axElement, kAXSelectedTextAttribute as CFString, evaluated.text as CFString) == .success else {
            return false
        }

        return true
    }

    /// Strategy B: Simulated Backspace + NSPasteboard Cmd+V fallback for web/electron text controls.
    private static func replaceViaKeystrokeSimulation(prefixLength: Int, evaluated: EvaluatedTemplate) {
        defer {
            // Keep isReplacing = true during event posting + 150ms buffer to absorb synthetic events
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isReplacing = false
            }
        }

        let expansionText = evaluated.text
        let src = hidSource

        // 1. Delete typed abbreviation prefix by posting Backspace CGEvent N times
        for _ in 0..<prefixLength {
            if let backspaceDown = CGEvent(keyboardEventSource: src, virtualKey: 0x33, keyDown: true) {
                backspaceDown.post(tap: .cgSessionEventTap)
            }
            if let backspaceUp = CGEvent(keyboardEventSource: src, virtualKey: 0x33, keyDown: false) {
                backspaceUp.post(tap: .cgSessionEventTap)
            }
            usleep(1000) // 1ms delay between key events (running off-main thread)
        }

        guard !expansionText.isEmpty else { return }

        // 2. Safely snapshot all existing pasteboard items (supporting text, RTF, images, and custom UTTypes)
        let pasteboard = NSPasteboard.general
        var savedItems: [[(NSPasteboard.PasteboardType, Data)]] = []

        if let items = pasteboard.pasteboardItems {
            for item in items {
                var itemTypes: [(NSPasteboard.PasteboardType, Data)] = []
                for type in item.types {
                    if let data = item.data(forType: type) {
                        itemTypes.append((type, data))
                    }
                }
                if !itemTypes.isEmpty {
                    savedItems.append(itemTypes)
                }
            }
        }

        // 3. Write expansion text and record the resulting changeCount
        pasteboard.clearContents()
        pasteboard.setString(expansionText, forType: .string)
        let expansionChangeCount = pasteboard.changeCount

        usleep(5000) // 5ms delay before posting Cmd+V

        // 4. Post Command Key Down (0x37), V Key Down (0x09), V Key Up (0x09), Command Key Up (0x37)
        if let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: true) {
            cmdDown.post(tap: .cgSessionEventTap)
        }
        if let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true) {
            vDown.flags = .maskCommand
            vDown.post(tap: .cgSessionEventTap)
        }
        if let vUp = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false) {
            vUp.flags = .maskCommand
            vUp.post(tap: .cgSessionEventTap)
        }
        if let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: false) {
            cmdUp.post(tap: .cgSessionEventTap)
        }

        // 5. Safely restore previous pasteboard content after delay without clobbering new user copies
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // Only restore if pasteboard changeCount matches our expansion changeCount.
            // If the user or another app copied something in the interim, do NOT overwrite it!
            guard pasteboard.changeCount == expansionChangeCount else { return }

            guard !savedItems.isEmpty else {
                pasteboard.clearContents()
                return
            }

            pasteboard.clearContents()
            let itemsToRestore = savedItems.map { itemTypes -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in itemTypes {
                    item.setData(data, forType: type)
                }
                return item
            }
            pasteboard.writeObjects(itemsToRestore)
        }
    }
}
