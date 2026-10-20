import Foundation
import AppKit
import CoreGraphics
import Carbon

/// System-wide Event Monitor Service using CGEventTap & NSEvent.
/// Intercepts keys system-wide across macOS applications.
public final class EventMonitor {

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var localMonitor: Any?
    private var retryTimer: Timer?

    public var stateMachine: StateMachine
    public weak var overlayPanel: OverlayPanel?

    /// Optional replacement delegate for testing and sandboxing.
    /// When non-nil, EventMonitor dispatches replacements here instead of invoking TextReplacer.
    public var onReplace: ((_ prefixLength: Int, _ evaluated: EvaluatedTemplate) -> Void)? = nil

    private func executeReplacement(prefixLength: Int, evaluated: EvaluatedTemplate) {
        if let onReplace = self.onReplace {
            onReplace(prefixLength, evaluated)
        } else {
            TextReplacer.replace(prefixLength: prefixLength, evaluated: evaluated)
        }
    }

    public init(stateMachine: StateMachine) {
        self.stateMachine = stateMachine
    }

    /// Starts monitoring keystrokes globally via CGEventTap and locally via NSEvent.
    public func start() {
        stop()

        // 1. Local NSEvent monitor (fallback when CGEventTap is inactive)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self = self else { return event }
            if self.eventTap == nil {
                if self.handleNSEvent(event) {
                    return nil // Consume event locally
                }
            }
            return event
        }

        // 2. Global CGEventTap for system-wide key interception across all macOS apps
        setupCGEventTap()

        // 3. Periodic timer to retry CGEventTap setup if permissions were granted after app start
        retryTimer = Timer.scheduledTimer(withTimeInterval: AppConfig.accessibilityRetryInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.eventTap == nil {
                self.setupCGEventTap()
            }
        }
    }

    /// Stops keystroke event monitors.
    public func stop() {
        retryTimer?.invalidate()
        retryTimer = nil

        if let local = localMonitor {
            NSEvent.removeMonitor(local)
            localMonitor = nil
        }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let src = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
                runLoopSource = nil
            }
            eventTap = nil
        }
    }

    private func setupCGEventTap() {
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.leftMouseDown.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<EventMonitor>.fromOpaque(refcon).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = monitor.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }

            if monitor.handleCGEvent(event, type: type) {
                return nil // Consume CGEvent system-wide!
            }

            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            return
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// Low-level CGEvent handler. Returns true to consume event system-wide.
    public func handleCGEvent(_ event: CGEvent, type: CGEventType) -> Bool {
        // 0. Gate out secure input fields (passwords, PINs, master keys)
        if IsSecureEventInputEnabled() {
            if stateMachine.state != .idle {
                stateMachine.reset(state: .idle)
            }
            return false
        }

        // DO NOT WATCH KEYSTROKES WHILE REPLACING TEXT!
        if TextReplacer.isReplacing {
            return false
        }

        if type == .leftMouseDown {
            // Any click may move the caret, so the typed buffer no longer describes the text before it
            if stateMachine.state != .idle {
                // Check if mouse click occurred inside the floating overlay panel frame
                let cocoaMouseLocation = NSEvent.mouseLocation
                if let panel = overlayPanel, panel.isVisible {
                    if panel.frame.contains(cocoaMouseLocation) {
                        // Mouse click IS inside overlay panel! Do NOT dismiss state machine; let overlay process row click!
                        return false
                    }
                }

                // Mouse click outside overlay panel: reset buffer and dismiss popup state
                DispatchQueue.main.async { [weak self] in
                    self?.stateMachine.reset(state: .idle)
                }
            }
            return false
        }

        guard type == .keyDown else { return false }

        let flags = event.flags
        let isCommandPressed = flags.contains(.maskCommand)
        let isOptionPressed = flags.contains(.maskAlternate)
        let isControlPressed = flags.contains(.maskControl)

        // 1. Fast-path: Command or Option shortcuts reset state machine immediately with zero allocation
        if isCommandPressed || isOptionPressed {
            if stateMachine.state != .idle {
                stateMachine.reset(state: .idle)
            }
            return false
        }

        let keyCode = Int64(event.getIntegerValueField(.keyboardEventKeycode))

        // 2. Fast-path: Escape (0x35)
        if keyCode == 0x35 {
            stateMachine.cancel()
            return false
        }

        // 3. Fast-path: Backspace (0x33)
        if keyCode == 0x33 {
            stateMachine.processBackspace()
            return false
        }

        // 4. Accept Expansion with Tab (0x30) or Return/Enter (0x24 / 0x4C)
        let isTab = (keyCode == 0x30)
        let isEnter = (keyCode == 0x24 || keyCode == 0x4C)

        if isTab || isEnter {
            // Tab only expands once the popup is on screen; before that it is the app's Tab (indent, accept completion, next field)
            let isPopupShown = overlayPanel?.isVisible ?? true
            if stateMachine.state == .popupActive && (isEnter || isPopupShown) {
                if isEnter && !stateMachine.isSelectionForced {
                    // Enter key pressed WITHOUT prior arrow navigation: do NOT expand!
                    // Reset state and pass Enter key through to application
                    stateMachine.reset(state: .idle)
                    return false
                }

                // If Tab is pressed without explicit selection, default to the first candidate (index 0).
                // If Enter is pressed, isSelectionForced is guaranteed true, so targetIndex is selectedIndex.
                let targetIndex: Int = stateMachine.selectedIndex ?? 0
                if let expansionResult = stateMachine.processSelectionToExpand(index: targetIndex) {
                    executeReplacement(prefixLength: expansionResult.prefixLength, evaluated: expansionResult.evaluated)
                    return true // Consume Tab / Enter event system-wide!
                }
            }
            if stateMachine.state != .idle {
                stateMachine.reset(state: .idle)
            }
            return false
        }

        // 5. Arrow Keys Navigation (Up: 0x7E, Down: 0x7D, Left: 0x7B, Right: 0x7C)
        if keyCode == 0x7E || keyCode == 0x7D {
            if stateMachine.state == .popupActive {
                let dir: NavigationDirection = (keyCode == 0x7E) ? .up : .down
                stateMachine.navigateSelection(direction: dir)
                return true
            } else {
                if stateMachine.state != .idle {
                    stateMachine.reset(state: .idle)
                }
                return false
            }
        }

        if keyCode == 0x7B || keyCode == 0x7C {
            if stateMachine.state != .idle {
                stateMachine.reset(state: .idle)
            }
            return false
        }

        // 6. Fast-path: Space (0x31)
        if keyCode == 0x31 {
            if stateMachine.state != .idle {
                stateMachine.reset(state: .idle)
            }
            return false
        }

        // 7. Ignore Function keys (F1-F12: 0x60..0x79)
        if (keyCode >= 0x60 && keyCode <= 0x79) {
            if stateMachine.state != .idle {
                stateMachine.reset(state: .idle)
            }
            return false
        }

        // 8. Control Shortcuts when popup active: Ctrl+j, Ctrl+k, Ctrl+n, Ctrl+p, Ctrl+l
        if isControlPressed {
            if stateMachine.state == .popupActive {
                // Keycodes: j = 0x26, k = 0x28, n = 0x2D, p = 0x23, l = 0x25
                if keyCode == 0x26 || keyCode == 0x2D { // j or n -> Down
                    stateMachine.navigateSelection(direction: .down)
                    return true
                } else if keyCode == 0x28 || keyCode == 0x23 { // k or p -> Up
                    stateMachine.navigateSelection(direction: .up)
                    return true
                } else if keyCode == 0x25 { // l -> Expand
                    let targetIndex = stateMachine.selectedIndex ?? 0
                    if let expansionResult = stateMachine.processSelectionToExpand(index: targetIndex) {
                        executeReplacement(prefixLength: expansionResult.prefixLength, evaluated: expansionResult.evaluated)
                        return true
                    }
                }
            }
            if stateMachine.state != .idle {
                stateMachine.reset(state: .idle)
            }
            return false
        }

        // 9. Zero-allocation Unicode character retrieval directly from CGEvent
        var chars: (UniChar, UniChar, UniChar, UniChar) = (0, 0, 0, 0)
        var actualLength = 0
        withUnsafeMutablePointer(to: &chars) { ptr in
            ptr.withMemoryRebound(to: UniChar.self, capacity: 4) { uniPtr in
                event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &actualLength, unicodeString: uniPtr)
            }
        }

        if actualLength > 0 {
            let uVal = chars.0
            if (uVal >= 0xF700 && uVal <= 0xF8FF) || uVal < 0x20 || uVal == 0x7F {
                if stateMachine.state != .idle {
                    stateMachine.reset(state: .idle)
                }
                return false
            }

            if let scalar = UnicodeScalar(uVal) {
                let char = Character(scalar)
                if char.isWhitespace || char.isNewline {
                    if stateMachine.state != .idle {
                        stateMachine.reset(state: .idle)
                    }
                    return false
                }
                if char.isLetter || char.isNumber || char.isPunctuation || char.isSymbol {
                    stateMachine.processCharacter(char)
                }
            }
        }

        return false
    }

    /// Fallback NSEvent router for local event monitoring when accessibility tap is disabled.
    public func handleNSEvent(_ event: NSEvent) -> Bool {
        guard let cgEvent = event.cgEvent else { return false }
        return handleCGEvent(cgEvent, type: .keyDown)
    }
}

