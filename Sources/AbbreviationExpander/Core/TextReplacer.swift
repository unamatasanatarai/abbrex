import Foundation
import AppKit
import CoreGraphics
import ApplicationServices

/// Text Replacement Engine using AXUIElement Accessibility APIs with CGEvent fallback.
public final class TextReplacer {

    private static let systemWide = AXUIElementCreateSystemWide()
    private static let hidSource = CGEventSource(stateID: .hidSystemState)

    /// Guard flag: when true, event monitor ignores all keystrokes to prevent catching synthetic replacement events.
    public static var isReplacing: Bool = false

    /// Replaces the typed abbreviation prefix with expanded template content.
    /// - Parameters:
    ///   - prefixLength: Number of characters typed in abbreviation to backspace/delete.
    ///   - evaluated: Evaluated template text content.
    public static func replace(prefixLength: Int, evaluated: EvaluatedTemplate) {
        isReplacing = true

        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isReplacing = false
            }
        }

        // Strategy A: Try Native macOS Accessibility API replacement (Fast, precise, zero clipboard side-effects)
        if replaceViaAccessibility(prefixLength: prefixLength, evaluated: evaluated) {
            return
        }

        // Strategy B: Fallback to simulated Backspaces + NSPasteboard Cmd+V
        replaceViaKeystrokeSimulation(prefixLength: prefixLength, evaluated: evaluated)
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
            usleep(2000)
        }

        guard !expansionText.isEmpty else { return }

        // 2. Paste expansion text via NSPasteboard & Cmd+V
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(expansionText, forType: .string)

        usleep(10000) // 10ms delay before posting Cmd+V

        // Post Command Key Down (0x37), V Key Down (0x09), V Key Up (0x09), Command Key Up (0x37)
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

        // Restore previous pasteboard content after delay
        if let prev = previousString {
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.3) {
                pasteboard.clearContents()
                pasteboard.setString(prev, forType: .string)
            }
        }
    }
}
