import Foundation
import AppKit
import CoreGraphics

/// System-wide Event Monitor Service using CGEventTap & NSEvent.
/// Intercepts keys system-wide across macOS applications.
public final class EventMonitor {

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var localMonitor: Any?
    private var retryTimer: Timer?

    public var stateMachine: StateMachine
    public weak var overlayPanel: OverlayPanel?
    public var onExpandTriggered: ((ExpansionResult) -> Void)?
    public var onCaretPositionUpdate: ((CaretTracker.CaretRect) -> Void)?

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
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
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
        // DO NOT WATCH KEYSTROKES WHILE REPLACING TEXT!
        if TextReplacer.isReplacing {
            return false
        }

        if type == .leftMouseDown {
            if stateMachine.state == .popupActive {
                // Check if mouse click occurred inside the floating overlay panel frame
                let cocoaMouseLocation = NSEvent.mouseLocation
                if let panel = overlayPanel, panel.isVisible {
                    if panel.frame.contains(cocoaMouseLocation) {
                        // Mouse click IS inside overlay panel! Do NOT dismiss state machine; let overlay process row click!
                        return false
                    }
                }

                // Mouse click outside overlay panel: dismiss popup state
                DispatchQueue.main.async { [weak self] in
                    self?.stateMachine.reset(state: .idle)
                }
            }
            return false
        }

        guard type == .keyDown else { return false }
        guard let nsEvent = NSEvent(cgEvent: event) else { return false }

        return handleNSEvent(nsEvent)
    }

    /// Keydown event router and state machine interceptor.
    /// Returns true if the event should be consumed.
    public func handleNSEvent(_ event: NSEvent) -> Bool {
        // DO NOT WATCH KEYSTROKES WHILE REPLACING TEXT!
        if TextReplacer.isReplacing {
            return false
        }

        let keyCode = event.keyCode
        let flags = event.modifierFlags
        let isControlPressed = flags.contains(.control)
        let isCommandPressed = flags.contains(.command)
        let isOptionPressed = flags.contains(.option)

        // 1. Command or Option shortcuts reset state machine
        if isCommandPressed || isOptionPressed {
            stateMachine.reset(state: .idle)
            return false
        }

        // 2. Control Shortcuts: Allow Ctrl+j / Ctrl+k / Ctrl+n / Ctrl+p navigation and Ctrl+l selection when popup is active
        if isControlPressed {
            if stateMachine.state == .popupActive {
                if let chars = event.charactersIgnoringModifiers?.lowercased() {
                    if chars == "j" || chars == "n" { // Down / Next candidate
                        stateMachine.navigateSelection(direction: .down)
                        return true
                    } else if chars == "k" || chars == "p" { // Up / Previous candidate
                        stateMachine.navigateSelection(direction: .up)
                        return true
                    } else if chars == "l" { // Select expansion (works as Enter)
                        if let expansionResult = stateMachine.processSelectionToExpand() {
                            onExpandTriggered?(expansionResult)
                            TextReplacer.replace(prefixLength: expansionResult.prefixLength, evaluated: expansionResult.evaluated)
                            return true // Consume Ctrl+l system-wide!
                        }
                    }
                }
            }
            stateMachine.reset(state: .idle)
            return false
        }

        // 2. Accept Expansion with Tab (0x30) or Return/Enter (0x24 / 0x4C)
        if keyCode == 0x30 || keyCode == 0x24 || keyCode == 0x4C {
            if stateMachine.state == .popupActive {
                if let expansionResult = stateMachine.processSelectionToExpand() {
                    onExpandTriggered?(expansionResult)
                    TextReplacer.replace(prefixLength: expansionResult.prefixLength, evaluated: expansionResult.evaluated)
                    return true // Consume Tab / Enter event system-wide!
                }
            }
            stateMachine.reset(state: .idle)
            return false
        }

        // 4. Arrow Keys Navigation (Up: 0x7E, Down: 0x7D, Left: 0x7B, Right: 0x7C)
        if keyCode == 0x7E || keyCode == 0x7D {
            if stateMachine.state == .popupActive {
                let dir: NavigationDirection = (keyCode == 0x7E) ? .up : .down
                stateMachine.navigateSelection(direction: dir)
                return true
            } else {
                stateMachine.reset(state: .idle)
                return false
            }
        }

        if keyCode == 0x7B || keyCode == 0x7C {
            stateMachine.reset(state: .idle)
            return false
        }

        // 5. Escape key (0x35)
        if keyCode == 0x35 {
            stateMachine.cancel()
            return false
        }

        // 6. Backspace key (0x33)
        if keyCode == 0x33 {
            stateMachine.processBackspace()
            if stateMachine.state == .popupActive {
                let rect = CaretTracker.getCaretScreenPosition()
                onCaretPositionUpdate?(rect)
            }
            return false
        }

        // 7. Ignore Function keys (F1-F12: 0x60..0x79) and Navigation keys
        if (keyCode >= 0x60 && keyCode <= 0x79) {
            stateMachine.reset(state: .idle)
            return false
        }

        // 8. Printable Character Input
        if let characters = event.characters, !characters.isEmpty {
            let char = characters.first!

            if char.isWhitespace || char.isNewline {
                stateMachine.reset(state: .idle)
                return false
            }

            let unicodeVal = char.utf16.first ?? 0
            let isControlOrFunctionKey = (unicodeVal >= 0xF700 && unicodeVal <= 0xF8FF) || (unicodeVal < 0x20 || unicodeVal == 0x7F)

            if !isControlOrFunctionKey && (char.isLetter || char.isNumber || char.isPunctuation || char.isSymbol) {
                stateMachine.processCharacter(char)

                if stateMachine.state == .popupActive {
                    let rect = CaretTracker.getCaretScreenPosition()
                    onCaretPositionUpdate?(rect)
                }
            }
        }

        return false
    }
}

